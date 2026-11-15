import Foundation

/// Ограничения по времени, чтобы решение никогда не «висело» бесконечно.
enum Deadline {
    struct Exceeded: Error, Sendable {}

    /// Выполняет синхронную тяжёлую работу (точные решатели) в фоне и ждёт её не дольше `seconds`.
    ///
    /// Синхронный код нельзя прервать снаружи, поэтому при превышении лимита мы просто
    /// перестаём ждать и возвращаем `nil`; фоновая работа завершится сама и её результат отбросится.
    static func compute<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = ResumeOnce(continuation)
            Task.detached(priority: .userInitiated) {
                gate.resume(work())
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                gate.resume(nil)
            }
        }
    }

    /// Асинхронная операция с лимитом времени. Операция должна поддерживать отмену
    /// (сетевые запросы её поддерживают): при превышении лимита она отменяется и бросается `Exceeded`.
    static func run<T: Sendable>(
        seconds: Double, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw Exceeded()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw Exceeded() }
            return first
        }
    }
}

/// Продолжение, которое можно возобновить только один раз (первый пришедший результат побеждает).
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
