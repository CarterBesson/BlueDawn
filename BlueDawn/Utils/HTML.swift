// HTML.swift
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum HTML {
    static func toAttributed(_ html: String) -> AttributedString {
        guard let data = html.data(using: .utf8) else { return AttributedString(html) }

        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let ns = try? NSMutableAttributedString(data: data, options: opts, documentAttributes: nil) {
            let full = NSRange(location: 0, length: ns.length)
            // Strip attributes that break dark mode or layout; keep links.
            ns.removeAttribute(NSAttributedString.Key.font, range: full)
            ns.removeAttribute(NSAttributedString.Key.foregroundColor, range: full)
            ns.removeAttribute(NSAttributedString.Key.backgroundColor, range: full)
            return AttributedString(ns)
        }

        if let ns = try? NSAttributedString(data: data, options: opts, documentAttributes: nil) {
            return AttributedString(ns.string) // entity-decoded fallback
        }
        return AttributedString(html)
    }
}
