import Foundation

public struct PreRollBuffer: Sendable {
    public let capacity: Int
    private var storage: [Float] = []

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        storage.reserveCapacity(self.capacity)
    }

    public mutating func append(_ samples: [Float]) {
        guard capacity > 0, !samples.isEmpty else { return }
        storage.append(contentsOf: samples)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    public mutating func drain() -> [Float] {
        defer { storage.removeAll(keepingCapacity: true) }
        return storage
    }
}
