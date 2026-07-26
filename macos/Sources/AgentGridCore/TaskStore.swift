import Foundation

public struct TaskStore: Sendable {
    public private(set) var tasks: [TaskSnapshot]
    public var retention: TimeInterval
    public var capacity: Int

    public init(
        tasks: [TaskSnapshot] = [],
        retention: TimeInterval = 2 * 60 * 60,
        capacity: Int = 20
    ) {
        self.tasks = tasks
        self.retention = retention
        self.capacity = capacity
    }

    public mutating func upsert(_ task: TaskSnapshot) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        purge(now: task.updatedAt)
    }

    public mutating func remove(id: String) {
        tasks.removeAll { $0.id == id }
    }

    public mutating func purge(now: Date = .now) {
        tasks.removeAll { task in
            guard task.isTerminal, let completedAt = task.completedAt else {
                return false
            }
            return now.timeIntervalSince(completedAt) > retention
        }

        guard tasks.count > capacity else {
            return
        }

        let removable = tasks
            .filter(\.isTerminal)
            .sorted { $0.updatedAt < $1.updatedAt }
            .map(\.id)

        for id in removable where tasks.count > capacity {
            tasks.removeAll { $0.id == id }
        }
    }

    public func focusedTask() -> TaskSnapshot? {
        tasks.max { lhs, rhs in
            if lhs.effectivePriority == rhs.effectivePriority {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.effectivePriority < rhs.effectivePriority
        }
    }
}

