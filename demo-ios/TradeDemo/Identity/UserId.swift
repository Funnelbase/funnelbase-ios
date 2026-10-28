import CryptoKit
import Foundation

/// Turns a username into the stable user id the analytics backend sees.
///
/// There is no sign-up API in this demo, so the id has to come from the only thing the user
/// supplies. Deriving it from a hash means the same username always produces the same id — on a
/// relaunch, after a reinstall, and on a different device — which is what makes it usable as a
/// `user_id` at all. A random id would make every sign-in a new person.
///
/// SHA-256 rather than a hash of convenience: 32 bits collide at a few tens of thousands of
/// names, and this value is what a person's whole event history hangs off.
///
/// It is also the *same* derivation as the Android and Flutter demos' — byte for byte, which is
/// the point. "ada" signing in on an iPhone and "ada"
/// signing in on a phone next to it are one person on every page of the dashboard, so this
/// function is pinned by a test rather than merely covered by one.
enum UserId {

    /// - Parameter username: as typed. Trimmed and lowercased first, so " Ada " and "ada" are
    ///   one person rather than two — the same normalisation a real login would apply.
    static func forUsername(_ username: String) -> String {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        // 16 hex characters — 64 bits, which is plenty for a demo and short enough to read off
        // a screen and paste into a search.
        return "u_" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
