import Foundation
import CryptoKit

/// SHA-256, as hex. Used for the notification category identifier, which has to be the same string
/// the backend derived from the same buttons.
public enum Digest {
    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
