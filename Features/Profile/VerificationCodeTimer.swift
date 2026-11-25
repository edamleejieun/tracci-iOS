import Foundation

@MainActor
final class VerificationCodeTimer {
    private var timer: Timer?

    func start(seconds: Int, onTick: @escaping @MainActor (Int) -> Void) {
        invalidate()
        onTick(seconds)
        guard seconds > 0 else { return }

        var remaining = seconds
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] activeTimer in
            Task { @MainActor in
                guard let self else {
                    activeTimer.invalidate()
                    return
                }
                if remaining > 0 {
                    remaining -= 1
                    onTick(remaining)
                } else {
                    self.invalidate()
                }
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}