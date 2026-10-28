import Foundation

/// A pseudo-random generator that can be given a seed.
///
/// It exists because Swift's own generator cannot be seeded, and the tests below the data
/// generators assert the *shape* of values that are random by design — so a failure has to be
/// reproducible or it cannot be looked at twice. Kotlin hands `kotlin.random.Random(seed)` over;
/// this is the same idea, written out.
///
/// SplitMix64: one word of state, no warm-up, and a stream good enough for prices nobody trades
/// on. The algorithm is not the interesting part — that a seed reproduces a market exactly is.
///
/// A class rather than a struct so it is passed by reference the way Kotlin's is: a generator
/// copied by accident halfway through generating fifty instruments would silently repeat itself.
final class SeededRandom {

    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// A generator for a launch: a different market every time the app starts, which is what
    /// makes it self-evident that none of the data is real.
    static func unseeded() -> SeededRandom {
        SeededRandom(seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// `[0, 1)` — 53 bits, the whole mantissa of a Double and no more.
    func unit() -> Double {
        Double(next() >> 11) * 0x1p-53
    }

    /// `[low, high)`.
    func double(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * unit()
    }

    /// `[low, until)`, as `Random.nextInt(from, until)` reads in Kotlin.
    func int(_ low: Int, _ until: Int) -> Int {
        precondition(until > low, "an empty range has nothing to draw from")
        return low + Int(next() % UInt64(until - low))
    }

    func int64(_ low: Int64, _ until: Int64) -> Int64 {
        precondition(until > low, "an empty range has nothing to draw from")
        return low + Int64(next() % UInt64(until - low))
    }

    func bool() -> Bool {
        next() & 1 == 0
    }

    func element<T>(_ items: [T]) -> T {
        items[int(0, items.count)]
    }

    /// Fisher-Yates, so the result is a permutation and not a sort by a random key — which
    /// would consume a different number of draws depending on the sort and make the seed's
    /// reproducibility depend on the standard library's implementation.
    func shuffled<T>(_ items: [T]) -> [T] {
        var result = items
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            result.swapAt(index, int(0, index + 1))
        }
        return result
    }
}
