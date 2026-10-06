import Foundation

// MARK: - Lenient JSON decoding
//
// The Android app uses kotlinx.serialization with `isLenient = true`, which quietly accepts
// quoted numbers ("123"), numbers where strings are expected, and missing keys (defaults).
// Postgres BIGINT columns, for example, arrive as strings. These wrappers give Swift's
// `Codable` the same tolerance so one odd field never breaks a whole feed/response.
//
//   @Flex  var avgHeartRate: Int?     -> optional, nil when missing/invalid
//   @FlexD var like_count: Int = 0    -> non-optional with a default when missing/invalid

protocol FlexValue: Codable {
    static var flexDefault: Self { get }
    static func flexDecode(_ c: SingleValueDecodingContainer) -> Self?
}

extension Int: FlexValue {
    static var flexDefault: Int { 0 }
    static func flexDecode(_ c: SingleValueDecodingContainer) -> Int? {
        if let v = try? c.decode(Int.self) { return v }
        if let v = try? c.decode(Double.self), v.isFinite, abs(v) < 9.0e15 { return Int(v) }
        if let s = try? c.decode(String.self), let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite, abs(d) < 9.0e15 { return Int(d) }
        if let b = try? c.decode(Bool.self) { return b ? 1 : 0 }
        return nil
    }
}

extension Int64: FlexValue {
    static var flexDefault: Int64 { 0 }
    static func flexDecode(_ c: SingleValueDecodingContainer) -> Int64? {
        if let v = try? c.decode(Int64.self) { return v }
        if let v = try? c.decode(Double.self), v.isFinite, abs(v) < 9.0e15 { return Int64(v) }
        if let s = try? c.decode(String.self) {
            let t = s.trimmingCharacters(in: .whitespaces)
            if let v = Int64(t) { return v }
            if let d = Double(t), d.isFinite, abs(d) < 9.0e15 { return Int64(d) }
        }
        return nil
    }
}

extension Double: FlexValue {
    static var flexDefault: Double { 0 }
    static func flexDecode(_ c: SingleValueDecodingContainer) -> Double? {
        if let v = try? c.decode(Double.self) { return v }
        if let s = try? c.decode(String.self), let d = Double(s.trimmingCharacters(in: .whitespaces)) { return d }
        return nil
    }
}

extension String: FlexValue {
    static var flexDefault: String { "" }
    static func flexDecode(_ c: SingleValueDecodingContainer) -> String? {
        if let v = try? c.decode(String.self) { return v }
        if let v = try? c.decode(Int64.self) { return String(v) }
        if let v = try? c.decode(Double.self) {
            return v.truncatingRemainder(dividingBy: 1) == 0 && abs(v) < 9.0e15 ? String(Int64(v)) : String(v)
        }
        if let b = try? c.decode(Bool.self) { return b ? "true" : "false" }
        return nil
    }
}

extension Bool: FlexValue {
    static var flexDefault: Bool { false }
    static func flexDecode(_ c: SingleValueDecodingContainer) -> Bool? {
        if let v = try? c.decode(Bool.self) { return v }
        if let v = try? c.decode(Int.self) { return v != 0 }
        if let s = try? c.decode(String.self) { return ["true", "1", "yes"].contains(s.lowercased()) }
        return nil
    }
}

/// Optional lenient value.
@propertyWrapper
struct Flex<T: FlexValue>: Codable {
    var wrappedValue: T?

    init(wrappedValue: T?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        wrappedValue = c.decodeNil() ? nil : T.flexDecode(c)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = wrappedValue { try c.encode(v) } else { try c.encodeNil() }
    }
}

/// Non-optional lenient value with a type default (0, "", false).
@propertyWrapper
struct FlexD<T: FlexValue>: Codable {
    var wrappedValue: T

    init(wrappedValue: T) { self.wrappedValue = wrappedValue }
    init() { self.wrappedValue = T.flexDefault }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        wrappedValue = c.decodeNil() ? T.flexDefault : (T.flexDecode(c) ?? T.flexDefault)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    /// Missing key / bad type → nil instead of throwing.
    func decode<T>(_ type: Flex<T>.Type, forKey key: Key) throws -> Flex<T> {
        (try? decodeIfPresent(type, forKey: key)) ?? Flex(wrappedValue: nil)
    }

    /// Missing key / bad type → default instead of throwing.
    func decode<T>(_ type: FlexD<T>.Type, forKey key: Key) throws -> FlexD<T> {
        (try? decodeIfPresent(type, forKey: key)) ?? FlexD()
    }
}

extension KeyedEncodingContainer {
    /// Omit nil optionals from request bodies (matches kotlinx `encodeDefaults = false`).
    mutating func encode<T>(_ value: Flex<T>, forKey key: Key) throws {
        if let v = value.wrappedValue { try encode(v, forKey: key) }
    }
}
