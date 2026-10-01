import AppKit

/// Recognises the system "back" trackpad gesture inside one window: the two-finger
/// "swipe between pages" (when enabled in System Settings) and the three-finger swipe.
/// Only claims horizontal gestures while `canGoBack` is true, so normal scrolling is untouched.
@MainActor
final class SwipeBackMonitor {
    /// Touched from `deinit`, which is nonisolated; only ever mutated on the main thread.
    nonisolated(unsafe) private var monitor: Any?
    private let canGoBack: () -> Bool
    private let onBack: () -> Void

    init(canGoBack: @escaping () -> Bool, onBack: @escaping () -> Void) {
        self.canGoBack = canGoBack
        self.onBack = onBack
    }

    func start(window: @escaping () -> NSWindow?) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
            guard let self, event.window === window(), canGoBack() else { return event }
            switch event.type {
            case .swipe:
                // Positive deltaX is the "back" direction (Apple, Handling Trackpad Events).
                if event.deltaX > 0 { onBack(); return nil }
            case .scrollWheel:
                if trackTwoFingerSwipe(event) { return nil }
            default:
                break
            }
            return event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func trackTwoFingerSwipe(_ event: NSEvent) -> Bool {
        guard NSEvent.isSwipeTrackingFromScrollEventsEnabled, event.phase == .began,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
        // Only claim the "back" direction (fingers moving right); forward swipes pass through untouched.
        // scrollingDeltaX follows the content, so its sign flips with the Natural Scrolling setting.
        let fingersMovingRight = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX > 0 : event.scrollingDeltaX < 0
        guard fingersMovingRight else { return false }
        var triggered = false
        event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                              dampenAmountThresholdMin: -1, max: 1) { [weak self] amount, _, isComplete, _ in
            // A positive gesture amount is a swipe toward "previous"/back.
            if isComplete, amount > 0, !triggered {
                triggered = true
                self?.onBack()
            }
        }
        return true
    }
}
