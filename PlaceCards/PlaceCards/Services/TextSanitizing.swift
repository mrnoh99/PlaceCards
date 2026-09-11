import Foundation

extension String {
    /// Strips every Unicode "format" character (`Cf` general category) —
    /// zero-width spaces/joiners, byte-order marks, and bidi
    /// direction-control marks (LRM/RLM, embeddings, overrides, isolates)
    /// among them. These are invisible by design, so removing them never
    /// changes what a string *looks* like it should say — but SwiftUI's
    /// `Text` can visibly mis-render around one sitting at the start of a
    /// string (part of the text appearing shifted/clipped at the leading
    /// edge), which is exactly what showed up for place names/addresses
    /// pulled from Google Places' API response text: Google is known to
    /// embed LRM marks in mixed-script (Korean + Latin/numeric) address
    /// strings for correct bidi display in a browser — harmless there,
    /// not in a plain `Text` view. Applied at the point each of those
    /// strings enters this app (`GooglePlace`/`NaverLocalItem`'s own
    /// `toSearchResult()`, `SharedLinkParser`'s raw text splitting) rather
    /// than everywhere a name/address is displayed, so nothing downstream
    /// needs to know this was ever a concern — and, since a card saved
    /// before this existed (or through a source path that missed a field)
    /// would otherwise stay broken forever, also re-applied to every
    /// already-saved card's text fields on load
    /// (`PlaceCard.strippingInvisibleFormatCharacters()`,
    /// `StorageService.loadPlaceCards()`).
    func strippingInvisibleFormatCharacters() -> String {
        let scalars = unicodeScalars.filter { $0.properties.generalCategory != .format }
        guard scalars.count != unicodeScalars.count else { return self }
        var result = ""
        result.unicodeScalars.append(contentsOf: scalars)
        return result
    }
}
