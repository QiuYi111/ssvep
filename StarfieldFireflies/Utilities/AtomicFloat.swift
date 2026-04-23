import Foundation

final class AtomicFloat: @unchecked Sendable {
    private var value: Float
    private var lock = NSLock()

    init(_ value: Float = 0.0) {
        self.value = value
    }

    var atomicValue: Float {
        lock.lock()
        let v = value
        lock.unlock()
        return v
    }

    func load() -> Float {
        lock.lock()
        let v = value
        lock.unlock()
        return v
    }

    func store(_ newValue: Float) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
