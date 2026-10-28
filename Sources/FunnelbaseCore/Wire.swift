import Foundation

/// The `/v1/events` wire format, as docs/event-contract.md describes it.
///
/// A copy of the shape rather than a shared module, for the same reason the Android SDK keeps its
/// own: the SDK ships inside someone else's app and must not drag server code along, and it has to
/// keep talking to an older backend after an app update. JSON is the contract; this is one end.
public struct RawEvent: Codable, Equatable, Sendable {
    public let eventId: String
    public let eventName: String
    public let occurredAt: String
    /// One stretch of use. Empty on a passive event, which starts no session and extends none.
    public let sessionId: String
    /// One stretch of use between resets: restarts at every sign-out and account switch.
    public let anonymousId: String
    /// One install: made on the first launch and never changed. A reinstall makes a new one.
    public let deviceId: String
    /// The account, while signed in. Absent rather than null when anonymous.
    public let userId: String?
    public let properties: [String: WireValue]
    public let traits: [String: WireValue]
    public let device: DeviceContext

    public init(
        eventId: String,
        eventName: String,
        occurredAt: String,
        sessionId: String,
        anonymousId: String,
        deviceId: String,
        userId: String? = nil,
        properties: [String: WireValue] = [:],
        traits: [String: WireValue] = [:],
        device: DeviceContext
    ) {
        self.eventId = eventId
        self.eventName = eventName
        self.occurredAt = occurredAt
        self.sessionId = sessionId
        self.anonymousId = anonymousId
        self.deviceId = deviceId
        self.userId = userId
        self.properties = properties
        self.traits = traits
        self.device = device
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventName = "event_name"
        case occurredAt = "occurred_at"
        case sessionId = "session_id"
        case anonymousId = "anonymous_id"
        case deviceId = "device_id"
        case userId = "user_id"
        case properties, traits, device
    }
}

/// A property or trait value, kept in the type it was sent as.
///
/// The platform stores numbers, strings and booleans in three typed columns, so `42` and `"42"`
/// are not the same thing downstream: a number can be filtered on a range, a string cannot. An
/// enum rather than `Any` is what makes that survive encoding.
public enum WireValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    /// What a caller passed, mapped onto the four the wire has. Anything else is described, as
    /// Android's `toString()` does, rather than dropped silently.
    public static func of(_ value: Any?) -> WireValue? {
        switch value {
        case nil: return nil
        case let value as String: return .string(value)
        case let value as Bool: return .bool(value)
        case let value as Int: return .integer(value)
        case let value as Double: return .number(value)
        case let value as Float: return .number(Double(value))
        case let value as any BinaryInteger: return .integer(Int(value))
        // Dates as ISO text, what a property or trait declared `date` accepts: a day as
        // `YYYY-MM-DD`, a moment in UTC with `Z` (Dates.swift). Before the catch-all below, which
        // would describe a `Date` as "2026-11-03 09:00:00 +0000" — not a date to the server.
        case let value as AnalyticsDay: return .string(value.description)
        case let value as Date: return .string(WireJson.moment(value))
        case let value as CustomStringConvertible: return .string(value.description)
        default: return nil
        }
    }
}

/// The device an event came from, collected once at startup.
public struct DeviceContext: Codable, Equatable, Sendable {
    public var platform: String
    public var osVersion: String?
    public var appVersion: String?
    public var deviceModel: String?
    public var deviceManufacturer: String?
    public var locale: String?
    public var timezone: String?
    /// Always nil: labelling events with a connection type is not worth the framework it needs.
    public var networkType: String?

    public init(
        platform: String = "ios",
        osVersion: String? = nil,
        appVersion: String? = nil,
        deviceModel: String? = nil,
        deviceManufacturer: String? = "Apple",
        locale: String? = nil,
        timezone: String? = nil,
        networkType: String? = nil
    ) {
        self.platform = platform
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.deviceManufacturer = deviceManufacturer
        self.locale = locale
        self.timezone = timezone
        self.networkType = networkType
    }

    enum CodingKeys: String, CodingKey {
        case platform
        case osVersion = "os_version"
        case appVersion = "app_version"
        case deviceModel = "device_model"
        case deviceManufacturer = "device_manufacturer"
        case locale, timezone
        case networkType = "network_type"
    }
}

/// Event names the backend reserves. The SDK sends these; a caller may not.
public enum ReservedEvents {
    public static let screenView = "$screen_view"
    public static let sessionStart = "$session_start"
    public static let identify = "$identify"
    public static let firstOpen = "$first_open"

    /// This install's push token, on issue and refresh, at every identify and reset, and when the
    /// notification permission changes.
    public static let pushToken = "$push_token"
    /// A push reached the device and was rendered.
    public static let pushReceived = "$push_received"
    /// The person tapped a push, or one of its buttons.
    public static let pushOpened = "$push_opened"

    /// The person switched a notification topic on or off. Passive: choosing in a settings screen
    /// is not a visit, and the choice becomes a row of the topic preferences, never of `events`.
    public static let topicPreference = "$topic_preference"

    /// The events nobody acted on: no session, and never a row in `events`.
    public static let passive: Set<String> = [pushToken, pushReceived, topicPreference]

    public static let screenViewScreenName = "screen_name"
    public static let firstOpenInstalledAtMs = "installed_at_ms"

    public static let pushTokenToken = "token"
    public static let pushTokenKind = "token_kind"
    public static let pushTokenStatus = "status"
    public static let pushDeliveryId = "delivery_id"
    public static let pushRunId = "run_id"
    public static let pushActionId = "action_id"

    public static let topicPreferenceTopic = "topic"
    public static let topicPreferenceSubscribed = "subscribed"
}

/// What kind of address a push token is, as the registry records it.
public enum TokenKinds {
    /// Firebase Cloud Messaging, which is how this SDK's demo reaches Apple devices today.
    public static let fcm = "fcm"
    /// An Apple device token, for a deployment that talks to Apple directly.
    public static let apns = "apns"
    /// An id some other gateway understands.
    public static let opaque = "opaque"
}

/// What a client may say about a token; `invalid` is the provider's verdict and only ever the server's.
public enum TokenStatuses {
    public static let active = "active"
    public static let disabled = "disabled"
}

public enum Sdk {
    public static let name = "ios"
    /// Bumped with the wire format. 0.1.0 is the first iOS release, at the Android SDK's 0.3.0
    /// contract; 0.2.0 adds notification topics (`$topic_preference` and `GET /v1/topics`).
    public static let version = "0.2.0"
}

/// One encoder and one decoder, configured the way the backend expects.
public enum WireJson {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    public static let decoder = JSONDecoder()

    /// An instant as the wire writes it: ISO 8601 in UTC, to milliseconds.
    public static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
