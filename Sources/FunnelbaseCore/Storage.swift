import Foundation

/// Where the SDK keeps its state, and why some of it is shared.
///
/// A notification service extension is a separate process with its own container. For a receipt it
/// records to reach the app's queue, and to be recorded under the same identity, both have to write
/// the same place — which on Apple platforms means an app group.
///
/// But an app group container **survives the app being deleted**, and identity must not: `device_id`
/// names the install, and a reinstall is a new install (docs/event-contract.md). A push
/// registration must not survive either, because the SDK only sends what changed, so a remembered
/// token is one it will never register again — which is how a reinstalled app goes silent.
///
/// So the two are split. Identity, sessions and the token registration live in the **app's own**
/// container, which the system does delete. The queue and the credentials the extension needs live
/// in the **group**, and a copy of identity is mirrored there so a receipt is recorded under the
/// same person. Without a group, everything falls back to the app's own container and push still
/// works: the extension sends the receipt itself and the app never sees it.
public enum Storage {

    /// The app's own store: identity, sessions and the push registration. Deleted with the app.
    public static func appDefaults() -> UserDefaults { .standard }

    /// The store both processes read: the group's, or the app's own when there is no group.
    public static func defaults(appGroup: String?) -> UserDefaults {
        guard let appGroup, let shared = UserDefaults(suiteName: appGroup) else { return .standard }
        return shared
    }

    /// Copies who this install is into the shared store, for the extension to record a receipt
    /// under. Called at startup and whenever identity changes, which is the only time it can.
    public static func mirrorIdentity(from identity: IdentityStore, into shared: UserDefaults) {
        shared.set(identity.deviceId, forKey: IdentityKeys.deviceId)
        shared.set(identity.anonymousId, forKey: IdentityKeys.anonymousId)
        if let userId = identity.userId {
            shared.set(userId, forKey: IdentityKeys.userId)
        } else {
            shared.removeObject(forKey: IdentityKeys.userId)
        }
    }

    /// The queue file, in the group container when there is one.
    public static func queueUrl(appGroup: String?, fileManager: FileManager = .default) -> URL {
        let directory = container(appGroup: appGroup, fileManager: fileManager)
        return directory.appendingPathComponent(queueFileName)
    }

    /// What the extension needs to upload on its own: the key and the endpoint, written by the app
    /// at `initialize` so the extension does not have to be configured twice.
    ///
    /// The key is already in the app's binary, so sharing it with the app's own extension gives
    /// away nothing that was not shipped.
    public static func writeCredentials(apiKey: String, endpoint: String, into defaults: UserDefaults) {
        defaults.set(apiKey, forKey: Keys.apiKey)
        defaults.set(endpoint, forKey: Keys.endpoint)
    }

    public static func credentials(from defaults: UserDefaults) -> (apiKey: String, endpoint: String)? {
        guard let apiKey = defaults.string(forKey: Keys.apiKey), !apiKey.isEmpty,
              let endpoint = defaults.string(forKey: Keys.endpoint), !endpoint.isEmpty
        else { return nil }
        return (apiKey, endpoint)
    }

    static func container(appGroup: String?, fileManager: FileManager) -> URL {
        if let appGroup, let shared = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return shared
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return support ?? fileManager.temporaryDirectory
    }

    public static let queueFileName = "analytics-queue.jsonl"

    private enum Keys {
        static let apiKey = "com.analytics.sdk.api_key"
        static let endpoint = "com.analytics.sdk.endpoint"
    }
}
