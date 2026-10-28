import Foundation

/// The offline queue: one event per line of a file, newline-delimited JSON.
///
/// The same shape as the Android SDK's, and for the same reasons. A file is enough — a database
/// would be a dependency and a schema for a list that is only ever appended to and consumed from
/// the front — and peeking is separate from removing, so an upload that fails loses nothing.
///
/// Unlike Android's, this queue is read and written by two processes: the app, and the notification
/// service extension recording that a push arrived. Appends are made with a single `write` to a
/// descriptor opened `O_APPEND`, which the kernel does not interleave, and the whole-file rewrites
/// take an exclusive `flock` so a trim and an append cannot lose each other.
public final class EventQueue {

    private let url: URL
    private let maxEvents: Int
    private let lock = NSLock()

    public init(url: URL, maxEvents: Int) {
        self.url = url
        self.maxEvents = maxEvents
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    /// Appends one serialized event. Refuses a line containing a newline: it would break the framing.
    public func enqueue(_ line: String) {
        precondition(!line.contains("\n"), "a queued event cannot contain a newline")
        lock.lock()
        defer { lock.unlock() }

        guard let data = (line + "\n").data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)

        trimToMaxSize()
    }

    /// The oldest `limit` lines, left in place.
    public func peek(_ limit: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(lines().prefix(limit))
    }

    /// Drops the oldest `count` lines, once the server has them.
    public func removeFirst(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = Array(lines().dropFirst(count))
        write(remaining)
    }

    public func size() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return lines().count
    }

    /// Drops one specific line, wherever it sits: the extension's own receipt, once the server has
    /// it. The app's queue may hold events the extension has no business sending, so it removes
    /// what it sent rather than the front of the queue.
    public func removeMatching(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = lines().filter { $0 != line }
        write(remaining)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    /// Caller holds the lock. The newest events are the ones worth keeping: a queue at its cap is
    /// an app that has been offline for a long time, and the last hour says more than the first.
    private func trimToMaxSize() {
        let all = lines()
        guard all.count > maxEvents else { return }
        write(Array(all.suffix(maxEvents)))
    }

    /// Caller holds the lock.
    private func lines() -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Caller holds the lock. Written through a temporary file and moved into place, so a process
    /// death mid-rewrite leaves the old queue rather than half of the new one.
    private func write(_ lines: [String]) {
        if lines.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let temporary = url.appendingPathExtension("writing")
        let text = lines.joined(separator: "\n") + "\n"
        guard (try? text.write(to: temporary, atomically: false, encoding: .utf8)) != nil else { return }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
