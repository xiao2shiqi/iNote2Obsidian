import Foundation

final class Scheduler {
    private var timer: Timer?

    func configure(interval: SyncInterval, action: @escaping () -> Void) {
        timer?.invalidate()
        guard let seconds = interval.seconds else { return }
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in action() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
