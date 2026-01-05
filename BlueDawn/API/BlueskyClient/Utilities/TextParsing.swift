import Foundation

extension BlueskyClient {
    func indexAtByteOffset(_ byteOffset: Int, in s: String) -> String.Index? {
        var i = s.startIndex
        var b = 0
        while true {
            if b == byteOffset { return i }
            guard i < s.endIndex else { break }
            b += s[i].utf8.count
            i = s.index(after: i)
        }
        return nil
    }

    func attributedFromBsky(text raw: String, facets: [Facet]?) -> AttributedString {
        var attr = AttributedString(raw)

        if let facets {
            for f in facets {
                guard let s = indexAtByteOffset(f.index.byteStart, in: raw),
                      let e = indexAtByteOffset(f.index.byteEnd, in: raw), s <= e else { continue }

                let lowerChars = raw.distance(from: raw.startIndex, to: s)
                let upperChars = raw.distance(from: raw.startIndex, to: e)
                let lower = attr.characters.index(attr.startIndex, offsetBy: lowerChars)
                let upper = attr.characters.index(attr.startIndex, offsetBy: upperChars)

                for feature in f.features {
                    switch feature {
                    case .link(let uri):
                        if let url = URL(string: uri) {
                            attr[lower..<upper].link = url
                        }
                    case .mention:
                        let visible = String(raw[s..<e])
                        let handle = visible.hasPrefix("@") ? String(visible.dropFirst()) : visible
                        if let url = URL(string: "bluesky://profile/\(handle)") {
                            attr[lower..<upper].link = url
                        }
                    default:
                        continue
                    }
                }
            }
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = raw as NSString
            let matches = detector.matches(in: raw, options: [], range: NSRange(location: 0, length: ns.length))
            for m in matches {
                guard let url = m.url, let r = Range(m.range, in: raw) else { continue }
                let lowerChars = raw.distance(from: raw.startIndex, to: r.lowerBound)
                let upperChars = raw.distance(from: raw.startIndex, to: r.upperBound)
                let lower = attr.characters.index(attr.startIndex, offsetBy: lowerChars)
                let upper = attr.characters.index(attr.startIndex, offsetBy: upperChars)
                if attr[lower..<upper].link == nil {
                    attr[lower..<upper].link = url
                }
            }
        }
        return attr
    }
}
