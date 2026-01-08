import Foundation

extension MastodonClient {
    // very light HTML→plain text conversion (avoids UIKit dependency)
    func htmlToAttributed(_ html: String) -> AttributedString {
        let withBreaks = html.replacingOccurrences(of: "<br ?/?>", with: "\n", options: .regularExpression)
        let stripped = withBreaks.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return AttributedString(stripped)
    }

    func parseISO8601(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f1.date(from: s) ?? f2.date(from: s)
    }

    // Try to find a linked Mastodon status URL in the content HTML.
    // Supports patterns like:
    //  - https://example.org/@user/123456789
    //  - https://example.org/users/user/statuses/123456789
    func extractLinkedStatus(fromHTML html: String) -> (host: String, id: String)? {
        // Very light anchor HREF extraction
        let pattern = #"<a[^>]+href=\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches {
            if m.numberOfRanges < 2 { continue }
            let urlStr = ns.substring(with: m.range(at: 1))
            guard let url = URL(string: urlStr) else { continue }
            guard let host = url.host else { continue }
            let comps = url.pathComponents.filter { $0 != "/" }
            // Patterns: /@user/<id> OR /users/<acct>/statuses/<id>
            if let last = comps.last, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: last)) {
                return (host, last)
            }
            if let idx = comps.firstIndex(of: "statuses"), idx + 1 < comps.count {
                let cand = comps[idx + 1]
                if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: cand)) {
                    return (host, cand)
                }
            }
        }
        return nil
    }
}
