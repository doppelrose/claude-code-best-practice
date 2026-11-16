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

    /// Асинхронная операция с лимитом времени.
    ///
    /// Результат приходит не позже чем через `seconds`, даже если операция не реагирует на отмену
    /// (например, системная модель или сторонний фреймворк): проигравшая задача отменяется,
    /// но её завершения мы не ждём. При превышении лимита бросается `Exceeded`,
    /// при отмене вызывающей задачи — `CancellationError`.
    static func run<T: Sendable>(
        seconds: Double, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = RunGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                gate.install(continuation)
                gate.track(
                    Task.detached(priority: Task.currentPriority) {
                        do {
                            gate.finish(.success(try await operation()))
                        } catch {
                            gate.finish(.failure(error))
                        }
                    })
                gate.track(
                    Task.detached {
                        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                        gate.finish(.failure(Exceeded()))
                    })
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}

/// Итог `Deadline.run`: первый результат (операция, тайм-аут или отмена) возобновляет продолжение,
/// остальные задачи отменяются и больше никого не задерживают.
private final class RunGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var result: Result<T, any Error>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<T, any Error>) {
        lock.lock()
        if let result {
            // Отмена пришла раньше, чем продолжение было установлено.
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func track(_ task: Task<Void, Never>) {
        lock.lock()
        let isFinished = result != nil
        if !isFinished { tasks.append(task) }
        lock.unlock()
        if isFinished { task.cancel() }
    }

    func finish(_ value: Result<T, any Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = value
        let pending = continuation
        continuation = nil
        let running = tasks
        tasks = []
        lock.unlock()
        running.forEach { $0.cancel() }
        pending?.resume(with: value)
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
