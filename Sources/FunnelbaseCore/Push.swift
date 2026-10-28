import Foundation

/// One action button under a notification. `id` is what the open reports as `action_id`.
public struct PushButton: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Where this button leads, overriding the message's own deep link.
    public let deepLink: String?

    public init(id: String, title: String, deepLink: String? = nil) {
        self.id = id
        self.title = title
        self.deepLink = deepLink
    }

    enum CodingKeys: String, CodingKey {
        case id, title
        case deepLink = "deep_link"
    }
}

/// A push the platform sent, as it arrived.
public struct PushPayload: Codable, Equatable, Sendable {
    public let deliveryId: String
    public let runId: String
    public let title: String
    public let body: String
    public let imageUrl: String?
    public let deepLink: String?
    public let collapseKey: String?
    /// The category the payload names, which the service extension registers the buttons under.
    public let category: String?
    public let buttons: [PushButton]
    /// Whatever the campaign added, without the keys the delivery layer uses.
    public let data: [String: String]

    public init(
        deliveryId: String,
        runId: String,
        title: String = "",
        body: String = "",
        imageUrl: String? = nil,
        deepLink: String? = nil,
        collapseKey: String? = nil,
        category: String? = nil,
        buttons: [PushButton] = [],
        data: [String: String] = [:]
    ) {
        self.deliveryId = deliveryId
        self.runId = runId
        self.title = title
        self.body = body
        self.imageUrl = imageUrl
        self.deepLink = deepLink
        self.collapseKey = collapseKey
        self.category = category
        self.buttons = buttons
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case deliveryId = "delivery_id"
        case runId = "run_id"
        case title, body, category, buttons, data
        case imageUrl = "image_url"
        case deepLink = "deep_link"
        case collapseKey = "collapse_key"
    }

    /// The link a tap followed: the button's own, if it had one, else the message's.
    public func link(forActionId actionId: String?) -> String? {
        if let actionId, let button = buttons.first(where: { $0.id == actionId }), let link = button.deepLink {
            return link
        }
        return deepLink
    }
}

/// Reads a push out of a notification's `userInfo`.
///
/// On Apple devices the delivery layer's `data` keys arrive as top-level keys of the payload,
/// beside `aps`, because that is what Firebase does with a data block — so the same strings the
/// Android SDK parses are here, one level up (docs/push.md, "The payload").
///
/// A push without both ids is not ours: there would be nothing to report a receipt against, and
/// another sender's notification may well reach the same app.
public enum PushParser {

    /// Keys the delivery layer itself uses; everything else is the campaign's own.
    static let reserved: Set<String> = [
        "delivery_id", "run_id", "title", "body", "image_url", "deep_link", "collapse_key",
        "android_channel_id", "buttons", "aps", "gcm.message_id", "google.c.a.e", "google.c.fid",
        "google.c.sender.id",
    ]

    /// Apple shows four buttons at most; the platform caps a message at three either way.
    static let maxButtons = 4

    public static func parse(_ userInfo: [AnyHashable: Any]) -> PushPayload? {
        let strings = userInfo.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String else { return }
            if let value = entry.value as? String { result[key] = value }
        }
        guard let deliveryId = strings["delivery_id"]?.trimmed, !deliveryId.isEmpty,
              let runId = strings["run_id"]?.trimmed, !runId.isEmpty
        else { return nil }

        let aps = userInfo["aps"] as? [AnyHashable: Any]
        let alert = aps?["alert"] as? [AnyHashable: Any]

        return PushPayload(
            deliveryId: deliveryId,
            runId: runId,
            // The text is in `aps.alert` for Apple to draw; the data copy is the fallback.
            title: (alert?["title"] as? String) ?? strings["title"] ?? "",
            body: (alert?["body"] as? String) ?? strings["body"] ?? "",
            imageUrl: strings["image_url"]?.nonEmpty,
            deepLink: strings["deep_link"]?.nonEmpty,
            collapseKey: strings["collapse_key"]?.nonEmpty,
            category: (aps?["category"] as? String)?.nonEmpty,
            buttons: buttons(strings["buttons"]),
            data: strings.filter { !reserved.contains($0.key) && !$0.key.hasPrefix("google.") }
        )
    }

    /// A broken button list costs the buttons, not the notification: the text is the message.
    static func buttons(_ encoded: String?) -> [PushButton] {
        guard let encoded, !encoded.isEmpty, let data = encoded.data(using: .utf8) else { return [] }
        guard let parsed = try? WireJson.decoder.decode([PushButton].self, from: data) else { return [] }
        return parsed
            .filter { !$0.id.trimmed.isEmpty && !$0.title.trimmed.isEmpty }
            .prefix(maxButtons)
            .map { $0 }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { trimmed.isEmpty ? nil : self }
}
