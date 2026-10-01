import AppKit
import LumenCore
import OSLog

/// Moves keyboard focus between the sidebar, category list and content (rules in `PaneNavigation`),
/// plus in and out of the two text fields. Lists and grids still handle their own ↑ ↓ and Return.
@MainActor
final class PaneKeyRouter {
    private static let log = Logger(subsystem: "app.lumen", category: "keyboard")

    private let model: AppModel
    /// Removed from `deinit`, which is nonisolated; only mutated on the main thread.
    nonisolated(unsafe) private var monitor: Any?

    init(model: AppModel) {
        self.model = model
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func start(window: @escaping () -> NSWindow?) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = window(), event.window === window, window.attachedSheet == nil,
                  !model.isPlayerPresented,
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return event }
            return handle(event, in: window) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        if let editor = window.firstResponder as? NSTextView { return leaveTextField(editor, event) }
        guard let key = Self.key(for: event), let pane = pane(in: window) else {
            Self.log.debug("key \(event.keyCode) ignored: no pane (responder \(String(describing: window.firstResponder)))")
            return false
        }
        Self.log.debug("key \(event.keyCode) in \(String(describing: pane))")

        // ↑ on the first category row continues up into the filter field.
        if pane == .categories, event.keyCode == 126, model.filter == .all {
            model.focusCategoryFilter()
            return true
        }

        let action = PaneNavigation.action(for: key, in: pane,
                                           contentHandlesHorizontal: true,
                                           showingDetail: !model.detailPath.isEmpty)
        switch action {
        case .focus(let target):
            move(to: target, in: window)
            return true
        case .goBack:
            model.goBack()
            move(to: .content, in: window)
            return true
        case .passThrough:
            return false
        }
    }

    // MARK: Columns

    /// Asks SwiftUI to focus the column, then checks on the next run loop and, if focus didn't land
    /// there (lists can ignore programmatic focus), makes that column's table first responder directly.
    private func move(to target: PaneNavigation.Pane, in window: NSWindow) {
        model.focus(target)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.pane(in: window) != target,
                  let column = Self.columns(in: window)?[safe: Self.index(of: target)],
                  let table = Self.firstTable(in: column) else { return }
            Self.log.debug("fallback focus to \(String(describing: target)) table")
            window.makeFirstResponder(table)
            self.model.focusedPane = target
        }
    }

    /// The column holding the first responder, from the view hierarchy; falls back to what the columns
    /// last reported (SwiftUI-focused grid tiles live in the hosting view, outside any column subview).
    private func pane(in window: NSWindow) -> PaneNavigation.Pane? {
        if let responder = window.firstResponder as? NSView, let columns = Self.columns(in: window) {
            for (index, column) in columns.enumerated() where responder.isDescendant(of: column) {
                let pane = Self.pane(at: index)
                model.focusedPane = pane
                return pane
            }
        }
        return model.focusedPane
    }

    private static func index(of pane: PaneNavigation.Pane) -> Int {
        switch pane {
        case .sidebar: 0
        case .categories: 1
        case .content: 2
        }
    }

    private static func pane(at index: Int) -> PaneNavigation.Pane {
        [.sidebar, .categories, .content][min(index, 2)]
    }

    private static weak var cachedSplitView: NSSplitView?

    /// NavigationSplitView's three columns are the arranged subviews of an NSSplitView. Found once and
    /// cached, since this runs on every navigation key press.
    private static func columns(in window: NSWindow) -> [NSView]? {
        if let split = cachedSplitView, split.window === window { return split.arrangedSubviews }
        func search(_ view: NSView) -> NSSplitView? {
            if let split = view as? NSSplitView, split.arrangedSubviews.count == 3 { return split }
            for child in view.subviews { if let found = search(child) { return found } }
            return nil
        }
        cachedSplitView = window.contentView.flatMap(search)
        return cachedSplitView?.arrangedSubviews
    }

    private static func firstTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews { if let found = firstTable(in: child) { return found } }
        return nil
    }

    /// Arrow keys leave a text field once the caret can't move further that way:
    /// - category filter: ↓ / Return / Esc → category list, ← at the start → sidebar, → at the end → content
    /// - search: ↓ → results
    private func leaveTextField(_ editor: NSTextView, _ event: NSEvent) -> Bool {
        let length = (editor.string as NSString).length
        let selection = editor.selectedRange()
        let atStart = selection.location == 0 && selection.length == 0
        let atEnd = selection.location == length && selection.length == 0
        // The field editor's delegate is the control being edited; the toolbar search is the only NSSearchField.
        let isSearch = editor.delegate is NSSearchField

        switch event.keyCode {
        case 125: // ↓
            guard let window = editor.window else { return false }
            move(to: isSearch ? .content : .categories, in: window)
        case 36, 76, 53: // Return, Enter, Esc (search keeps these for itself)
            guard !isSearch, let window = editor.window else { return false }
            move(to: .categories, in: window)
        case 123 where !isSearch && atStart: // ←
            guard let window = editor.window else { return false }
            move(to: .sidebar, in: window)
        case 124 where !isSearch && atEnd: // →
            guard let window = editor.window else { return false }
            move(to: .content, in: window)
        default:
            return false
        }
        return true
    }

    private static func key(for event: NSEvent) -> PaneNavigation.Key? {
        switch event.keyCode {
        case 48: event.modifierFlags.contains(.shift) ? .backTab : .tab
        case 124: .right
        case 123: .left
        case 36, 76: .enter
        case 53: .escape
        default: nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
