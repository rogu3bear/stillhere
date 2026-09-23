import Foundation

/// Pure extraction of a page `<title>` from the first 64 KB of a response body.
public enum TitleExtractor {
    public static let maxBytes = 64 * 1024
    public static let maxLength = 80

    public static func title(from data: Data) -> String? {
        title(from: String(decoding: data.prefix(maxBytes), as: UTF8.self))
    }

    public static func title(from html: String) -> String? {
        guard let range = html.range(of: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let element = html[range]
        guard let open = element.firstIndex(of: ">"), let close = element.range(of: "</", options: .backwards) else { return nil }
        let inner = element[element.index(after: open)..<close.lowerBound]
        let collapsed = decodeEntities(String(inner))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > maxLength ? String(collapsed.prefix(maxLength - 1)) + "…" : collapsed
    }

    static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "middot": "·", "bull": "•",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "copy": "©", "reg": "®", "trade": "™",
    ]

    /// Decodes named entities from the table above plus `&#N;` and `&#xN;`.
    /// Unknown or malformed entities are left as written.
    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = text[...]
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let afterAmp = rest.index(after: amp)
            if let semi = rest[afterAmp...].prefix(12).firstIndex(of: ";"),
               let decoded = decodeEntity(rest[afterAmp..<semi]) {
                result += decoded
                rest = rest[rest.index(after: semi)...]
            } else {
                result += "&"
                rest = rest[afterAmp...]
            }
        }
        return result + rest
    }

    private static func decodeEntity(_ body: Substring) -> String? {
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            return UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        if body.hasPrefix("#") {
            return UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[String(body)]
    }
}
