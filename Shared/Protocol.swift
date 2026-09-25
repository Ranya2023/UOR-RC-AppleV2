import Foundation
import CryptoKit

/// The UOR-RC wire protocol — identical to the Windows/Android version, so an
/// iPhone can drive the Windows PC and an Android phone can drive the Mac.
///
///  1. the computer shouts a UDP "beacon" on port 47801
///  2. the phone answers with proof it knows the PIN
///  3. the computer opens a TCP connection to the phone on port 47802
///  4. from then on: one JSON object per line, both ways
public enum Wire {
    public static let beaconPort: UInt16 = 47801
    public static let phonePort: UInt16 = 47802

    /// sha256("pin:nonce") — first 16 hex characters (same as the Windows app)
    public static func proof(pin: String, nonce: String) -> String {
        let digest = SHA256.hash(data: Data("\(pin):\(nonce)".utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    public static func nonce() -> String {
        (0..<6).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    public static func encode(_ object: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        data.append(0x0A)
        return data
    }

    public static func decode(_ line: String) -> [String: Any]? {
        guard let d = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }
}

/// Splits a stream of bytes into whole lines.
public final class LineBuffer {
    private var buffer = Data()
    public init() {}

    public func push(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let i = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<i)
            buffer.removeSubrange(buffer.startIndex...i)
            if let s = String(data: line, encoding: .utf8), !s.isEmpty { lines.append(s) }
        }
        if buffer.count > 8_000_000 { buffer.removeAll() }
        return lines
    }
}

public extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String { self[k] as? String ?? "" }
    func num(_ k: String) -> Double {
        if let d = self[k] as? Double { return d }
        if let i = self[k] as? Int { return Double(i) }
        if let n = self[k] as? NSNumber { return n.doubleValue }
        return 0
    }
    func int(_ k: String) -> Int { Int(num(k)) }
    func bool(_ k: String) -> Bool { self[k] as? Bool ?? false }
    func has(_ k: String) -> Bool { self[k] != nil }
}
