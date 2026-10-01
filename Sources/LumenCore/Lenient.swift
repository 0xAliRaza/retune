import Foundation

// Xtream panels are notoriously inconsistent: the same field can arrive as a string,
// an int, a float, a bool or null depending on panel version and the row. These helpers
// coerce whatever arrives into the type we want and never throw.
extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value ? "1" : "0" }
        return nil
    }

    /// A trimmed, non-empty string, or nil.
    func lenientText(_ key: Key) -> String? {
        guard let value = lenientString(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return Int(trimmed) ?? Double(trimmed).map { Int($0) }
        }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        return (lenientInt(key) ?? 0) != 0
    }

    func lenientURL(_ key: Key) -> URL? {
        URL(lenient: lenientText(key))
    }

    /// Unix timestamp encoded as number or string.
    func lenientDate(_ key: Key) -> Date? {
        guard let seconds = lenientDouble(key), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Accepts either a single string or an array of strings, returning the first usable URL.
    func lenientFirstURL(_ key: Key) -> URL? {
        if let list = try? decodeIfPresent([String].self, forKey: key) {
            return list.lazy.compactMap { URL(lenient: $0) }.first
        }
        return lenientURL(key)
    }
}

/// Decodes an element without failing the surrounding array when one row is malformed.
struct Failable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// A coding key that accepts any string, for dictionaries with dynamic keys.
struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = Int(stringValue)
    }

    init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension URL {
    /// Builds an http(s) URL from loosely formatted provider strings (escaped slashes, spaces, blanks).
    public init?(lenient raw: String?) {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "\\/", with: "/")
        guard text.lowercased().hasPrefix("http") else { return nil }
        if let url = URL(string: text) {
            self = url
        } else if let escaped = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: escaped) {
            self = url
        } else {
            return nil
        }
    }
}
