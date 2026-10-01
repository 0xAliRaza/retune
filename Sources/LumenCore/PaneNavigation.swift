import Foundation

/// Keyboard movement between the three browse columns (sidebar → categories → content).
public enum PaneNavigation {
    public enum Pane: Sendable, Equatable { case sidebar, categories, content }
    public enum Key: Sendable { case tab, backTab, right, left, enter, escape }

    public enum Action: Sendable, Equatable {
        case focus(Pane)
        /// Leave a detail page (movie/series) back to its list.
        case goBack
        /// Let the focused control handle the key itself (list selection, grid movement, opening items).
        case passThrough
    }

    /// - Parameters:
    ///   - contentHandlesHorizontal: grids use ← → to move between tiles, so they keep those keys.
    ///   - showingDetail: a movie/series page is pushed in the content column.
    public static func action(for key: Key, in pane: Pane, contentHandlesHorizontal: Bool, showingDetail: Bool) -> Action {
        switch (pane, key) {
        case (.sidebar, .tab), (.sidebar, .right), (.sidebar, .enter): return .focus(.categories)
        case (.sidebar, .backTab): return .focus(.content)
        case (.categories, .tab), (.categories, .right), (.categories, .enter): return .focus(.content)
        case (.categories, .backTab), (.categories, .left), (.categories, .escape): return .focus(.sidebar)
        case (.content, .escape): return showingDetail ? .goBack : .focus(.categories)
        case (.content, .tab): return .focus(.sidebar)
        case (.content, .backTab): return .focus(.categories)
        case (.content, .left): return contentHandlesHorizontal || showingDetail ? .passThrough : .focus(.categories)
        default: return .passThrough
        }
    }
}
