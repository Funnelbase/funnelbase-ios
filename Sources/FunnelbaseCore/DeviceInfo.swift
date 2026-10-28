import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The device context, read once at startup — all but ``region()``, which is read per event: the
/// phone's language and time zone can change while the app runs, and they pick a message's
/// language and clock.
///
/// Nothing here identifies a person. No advertising id, no vendor id, no serial: the SDK's own
/// `device_id` names the install and is the only identifier it keeps, which is what lets the
/// platform's regulatory posture stay as simple as it is.
public enum DeviceInfo {

    public static func collect(bundle: Bundle = .main) -> DeviceContext {
        DeviceContext(
            platform: "ios",
            osVersion: osVersion(),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            deviceModel: model(),
            deviceManufacturer: "Apple",
            locale: region().locale,
            timezone: region().timezone,
            networkType: nil
        )
    }

    /// The phone's language and time zone as they are now.
    ///
    /// The language is the first of the person's preferred languages — the app's own, where one is
    /// chosen for it in Settings — and not `Locale.current`, which is limited to the languages the
    /// app itself is translated into: an English-only app on a Turkish iPhone reports `en` there,
    /// and a template's Turkish copy would never be picked.
    public static func region() -> DeviceRegion {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return DeviceRegion(locale: languageTag(preferred), timezone: TimeZone.autoupdatingCurrent.identifier)
    }

    /// An Apple identifier as a language tag: `tr_TR@rg=dezzzz` becomes `tr-TR`.
    public static func languageTag(_ identifier: String) -> String {
        let bare = identifier.split(separator: "@", maxSplits: 1).first.map(String.init) ?? identifier
        return bare.replacingOccurrences(of: "_", with: "-")
    }

    /// When the OS says this install happened, in Unix epoch milliseconds.
    ///
    /// Apple offers no install date, so this is the creation date of the app's own documents
    /// directory: made when the container is, and surviving an app update. It is older than the
    /// SDK for anyone who had the app before analytics arrived, which is exactly what keeps every
    /// existing user from counting as new on the day the SDK ships.
    public static func installedAtMillis(fileManager: FileManager = .default) -> Int? {
        guard let container = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
              let created = try? fileManager.attributesOfItem(atPath: container.path)[.creationDate] as? Date
        else { return nil }
        return Int(created.timeIntervalSince1970 * 1000)
    }

    private static func osVersion() -> String? {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    /// The hardware identifier, such as `iPhone16,2`, which is what a dashboard can group by.
    /// `UIDevice.model` would say only "iPhone".
    private static func model() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) }
        }
        return identifier?.isEmpty == false ? identifier : nil
    }
}
