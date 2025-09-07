import Foundation

enum Network: Hashable, Codable {
    case mastodon(instance: String)
    case bluesky
}
