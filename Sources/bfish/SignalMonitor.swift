import Darwin
import Dispatch
import Foundation

final class SignalMonitor: @unchecked Sendable {
    private let signals: [Int32]
    private let stream: AsyncStream<Int32>
    private let continuation: AsyncStream<Int32>.Continuation
    private let sources: [DispatchSourceSignal]
    private let lock = NSLock()
    private var stopped = false

    init(signals: [Int32] = [SIGINT, SIGTERM]) {
        self.signals = signals
        var capturedContinuation: AsyncStream<Int32>.Continuation!
        self.stream = AsyncStream { capturedContinuation = $0 }
        self.continuation = capturedContinuation
        self.sources = signals.map { signalNumber in
            Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler { capturedContinuation.yield(signalNumber) }
            source.resume()
            return source
        }
    }

    func next() async -> Int32? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        lock.unlock()

        sources.forEach { $0.cancel() }
        continuation.finish()
        signals.forEach { Darwin.signal($0, SIG_DFL) }
    }

    deinit {
        stop()
    }
}
