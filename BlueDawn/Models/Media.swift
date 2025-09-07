import Foundation

struct Media: Hashable, Codable {
    enum Kind: String, Codable { case image, video, gif }
    var url: URL
    var altText: String?
    var kind: Kind
}
