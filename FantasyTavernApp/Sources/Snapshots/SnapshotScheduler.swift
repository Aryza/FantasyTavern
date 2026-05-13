import Foundation
import Observation

@Observable
final class SnapshotScheduler {
    private(set) var isDirty: Bool = false
    private let interval: TimeInterval
    private let perform: () -> Void
    private var timer: Timer?

    init(interval: TimeInterval = 600, perform: @escaping () -> Void) {
        self.interval = interval
        self.perform = perform
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fireIfDirty()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markDirty() {
        isDirty = true
    }

    func fireForTesting() {
        fireIfDirty()
    }

    private func fireIfDirty() {
        guard isDirty else { return }
        perform()
        isDirty = false
    }

    deinit { stop() }
}
