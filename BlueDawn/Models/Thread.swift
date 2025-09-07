import Foundation

struct ThreadItem: Identifiable {
    let id: String
    let post: UnifiedPost
    let depth: Int // 1 = direct reply to root; 2 = reply to reply, etc.
}
