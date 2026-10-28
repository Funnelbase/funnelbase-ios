import Foundation

/// What the notification service extension should do with an arriving push, decided before any
/// framework object exists — so the decisions are testable without a device, a simulator, or a
/// push at all.
///
/// The extension then builds what this says: a category to register for the buttons, an image to
/// download and attach, and the text to show.
public struct NotificationPlan: Equatable {

    /// The category identifier the buttons are registered under, or nil when there are none.
    ///
    /// Apple's rule is that buttons come from a category the app registered, and the payload only
    /// names one — so per-message buttons mean registering a category as the push arrives. The
    /// identifier comes from the payload, which the backend derives from the buttons themselves,
    /// so two pushes offering the same buttons share one category instead of registering thousands.
    public let categoryIdentifier: String?
    public let buttons: [PushButton]
    /// Only ever an https url: the extension downloads it, and Apple refuses plain http by default.
    public let imageUrl: URL?
    /// The thread the notification joins, which is how a collapse key groups on Apple devices.
    public let threadIdentifier: String?

    public init(categoryIdentifier: String?, buttons: [PushButton], imageUrl: URL?, threadIdentifier: String?) {
        self.categoryIdentifier = categoryIdentifier
        self.buttons = buttons
        self.imageUrl = imageUrl
        self.threadIdentifier = threadIdentifier
    }

    public static func of(_ payload: PushPayload, allowInsecureImages: Bool = false) -> NotificationPlan {
        NotificationPlan(
            categoryIdentifier: payload.buttons.isEmpty ? nil : (payload.category ?? derivedCategory(for: payload.buttons)),
            buttons: payload.buttons,
            imageUrl: imageUrl(payload.imageUrl, allowInsecure: allowInsecureImages),
            threadIdentifier: payload.collapseKey
        )
    }

    /// The category identifier for a set of buttons, should the payload not name one. The same
    /// shape the backend writes: `an_` and a digest, so the two agree without either asking.
    public static func derivedCategory(for buttons: [PushButton]) -> String {
        let text = buttons.map { "\($0.id)\u{1e}\($0.title)\u{1e}\($0.deepLink ?? "")" }.joined(separator: "\u{1f}")
        return "an_" + Digest.sha256Hex(text).prefix(12)
    }

    /// An image the extension will actually fetch.
    ///
    /// https only, unless the host says otherwise: a notification extension has the app's own
    /// transport-security rules, and a campaign that points at plain http silently fails there.
    /// `allowInsecureImages` exists for a laptop, where a local provider serves over http.
    static func imageUrl(_ value: String?, allowInsecure: Bool) -> URL? {
        guard let value, let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", allowInsecure { return url }
        return nil
    }
}
