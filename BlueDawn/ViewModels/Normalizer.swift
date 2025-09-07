import Foundation

enum Normalizer {
    /// Deduplicate posts by their `id`, preserving the first occurrence order.
    static func dedupe(_ posts: [UnifiedPost]) -> [UnifiedPost] {
        var seen = Set<String>()
        var result: [UnifiedPost] = []
        result.reserveCapacity(posts.count)
        for post in posts {
            if seen.insert(post.id).inserted {
                result.append(post)
            }
        }
        return result
    }
}
