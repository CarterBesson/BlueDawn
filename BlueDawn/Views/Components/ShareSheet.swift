import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var activities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: activities)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

