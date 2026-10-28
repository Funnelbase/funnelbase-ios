/// Lorem ipsum, generated rather than pasted.
///
/// Every screen that needs filler prose gets it from here so the demo has no wall of hardcoded
/// placeholder text to scroll past in the source. Sentences are assembled from the classic word
/// list with real punctuation and capitalisation, which is what makes the result read as prose
/// at a glance instead of as an obvious block of test data.
enum Lorem {

    private static let words: [String] = (
        "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor " +
        "incididunt ut labore et dolore magna aliqua enim ad minim veniam quis nostrud " +
        "exercitation ullamco laboris nisi aliquip ex ea commodo consequat duis aute irure " +
        "in reprehenderit voluptate velit esse cillum eu fugiat nulla pariatur excepteur " +
        "sint occaecat cupidatat non proident sunt culpa qui officia deserunt mollit anim " +
        "id est laborum perspiciatis unde omnis iste natus error accusantium doloremque"
    ).split(separator: " ").map(String.init)

    /// One sentence, capitalised and full-stopped. `wordCount` nil draws one, because a default
    /// argument cannot read the generator it would have to draw from.
    static func sentence(_ random: SeededRandom, wordCount: Int? = nil) -> String {
        let count = wordCount ?? random.int(8, 16)
        let sentence = (0..<count).map { _ in random.element(words) }.joined(separator: " ")
        return sentence.capitalizedFirst + "."
    }

    /// A paragraph of `sentences` sentences.
    static func paragraph(_ random: SeededRandom, sentences: Int? = nil) -> String {
        let count = sentences ?? random.int(3, 6)
        return (0..<count).map { _ in sentence(random) }.joined(separator: " ")
    }

    /// A headline: title-cased, no full stop.
    ///
    /// Deliberately shorter than a sentence — a headline that runs to sixteen words wraps to
    /// three lines in a list row and stops looking like a headline.
    static func headline(_ random: SeededRandom, wordCount: Int? = nil) -> String {
        let count = wordCount ?? random.int(4, 8)
        return (0..<count)
            .map { _ in random.element(words).capitalizedFirst }
            .joined(separator: " ")
    }
}

private extension String {
    /// `capitalized` would lowercase the rest of a word; only the first character is in question.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
