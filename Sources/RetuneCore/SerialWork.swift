import Foundation

/// Runs background file work strictly in order, so deleting a file can't be undone by a save still running.
public struct SerialWork {
    private var last: Task<Void, Never>?

    public init() {}

    public mutating func enqueue(_ work: @escaping @Sendable () -> Void) {
        last = Task.detached(priority: .utility) { [last] in
            await last?.value
            work()
        }
    }

    /// Waits for everything enqueued so far.
    public func finished() async {
        await last?.value
    }
}
