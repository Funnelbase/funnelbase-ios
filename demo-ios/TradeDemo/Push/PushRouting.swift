import Funnelbase

/// What the app does with a push once the SDK has reported it: where to go.
///
/// The SDK deliberately does not navigate — it cannot know this app's routes — so it hands the
/// payload over and this is the app's half of the contract. Pure, so the routing is testable
/// without a device: given a push, which route.
enum PushRouting {

    /// The scheme the demo's own deep links use, as the campaign writes them. The same scheme
    /// the Android demo answers to, so one campaign addresses both apps.
    static let scheme = "trade"

    /// The route a push should open, or nil to leave the app where it is. Understands the demo's
    /// two link shapes and ignores anything else, because a campaign can always be sent with a
    /// link this build does not know yet.
    ///
    ///     trade://instrument/AAPL  →  instrument/AAPL
    ///     trade://markets          →  markets
    static func routeFor(_ link: String?) -> String? {
        guard let link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let prefix = "\(scheme)://"
        guard link.hasPrefix(prefix) else { return nil }

        let parts = link.dropFirst(prefix.count)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.isEmpty }

        guard let first = parts.first else { return nil }
        if first == "instrument", parts.count >= 2 {
            return Routes.instrumentDetail(parts[1].uppercased())
        }
        if Tab.allCases.contains(where: { $0.route == first }) {
            return first
        }
        return nil
    }

    /// The link a tap followed: the button's own, if it had one, else the message's.
    ///
    /// The SDK answers this too (`PushPayload.link(forActionId:)`), and this calls it rather than
    /// deciding again — a second copy of the rule is how a button's link and the message's end up
    /// disagreeing. It keeps a name here because the pair of decisions, which link and which
    /// route, is what the app is responsible for and what the test covers together.
    static func linkFor(_ payload: PushPayload, actionId: String?) -> String? {
        payload.link(forActionId: actionId)
    }
}
