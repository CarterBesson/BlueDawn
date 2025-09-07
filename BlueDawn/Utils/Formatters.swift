import Foundation

enum Formatters {
    static let legacyNumber: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesSignificantDigits = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    static func shortCount(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return n.formatted(.number.notation(.compactName))
    }
}
