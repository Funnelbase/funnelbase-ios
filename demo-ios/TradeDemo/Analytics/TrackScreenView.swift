import Funnelbase
import SwiftUI

extension View {

    /// Reports a screen view. Apply once, to the body of every screen.
    ///
    /// `task(id:)` is the counterpart of the Android demo's `LaunchedEffect(name)`: it runs when
    /// the view appears, again when it appears afresh, and again if the name changes — so
    /// arriving at a screen, coming back to it, and switching tabs each produce exactly one
    /// event, while a re-render produces none. `onAppear` would do the same here; `task(id:)` is
    /// keyed on the name, which is the thing the event is about.
    ///
    /// No properties, on purpose: a screen view says where the user is and carries `screen_name`
    /// only. What they are looking at is a custom event (see `Events`), which the catalog can
    /// describe and the Events page can break down.
    ///
    /// `Analytics.screen` is a no-op when the SDK was never initialised (no ingest key
    /// configured), so nothing here needs to check for that.
    func trackScreenView(_ name: String) -> some View {
        task(id: name) { Analytics.screen(name) }
    }
}
