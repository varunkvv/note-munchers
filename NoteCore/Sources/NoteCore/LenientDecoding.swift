// Saved state must survive new fields. Synthesized Decodable fails on a missing key,
// which would throw away his progress after an update that adds a field. These
// decoders start from the defaults and take whatever keys are present.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, or fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
