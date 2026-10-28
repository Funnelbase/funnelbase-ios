/// Every custom event this app sends, in one place.
///
/// Unlike screen views these are not free: ingestion rejects a custom event the app's catalog
/// does not declare, so each name here needs a matching definition under Data → Event catalog
/// before the app runs against a fresh app id. docs/demo-app.md lists them with their properties.
///
/// Screen views carry `screen_name` and nothing else. Anything that describes *what* was looked
/// at rather than *where* the user is belongs here, as its own event.
enum Events {
    /// An instrument's detail page was shown.
    static let instrumentViewed = "instrument_viewed"

    /// Ticker of the instrument, on `instrumentViewed`.
    static let propertySymbol = "symbol"
}
