import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

struct ImageViewerState: Identifiable {
    let id = UUID()
    let post: UnifiedPost
    var index: Int
}

struct ImageViewer: View {
    let post: UnifiedPost
    @State var index: Int
    @State private var dragY: CGFloat = 0
    @State private var isZoomed: Bool = false
    @State private var showAltText: Bool = false
    @State private var isDownloading: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showActions: Bool = false
    private let dismissThreshold: CGFloat = 140
    @Environment(\.dismiss) private var dismiss

    private enum UI {
        static let controlSize: CGFloat = 36
        static let iconSize: CGFloat = 17
    }

    init(post: UnifiedPost, startIndex: Int) {
        self.post = post
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(backgroundOpacity).ignoresSafeArea()
            if post.media.isEmpty {
                ProgressView().tint(.white)
            } else {
                TabView(selection: $index) {
                    ForEach(Array(post.media.enumerated()), id: \.offset) { idx, m in
                        ZoomableAsyncImage(url: m.url, isZoomed: $isZoomed)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                // Reset zoom/alt state when changing pages so gestures behave predictably
                .onChange(of: index) { _, _ in
                    isZoomed = false
                    showAltText = false
                }
                .offset(y: dragY)
                .scaleEffect(1 - dragShrink)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .onChanged { value in
                            guard !isZoomed else { return }
                            // Only react primarily to vertical drags; ignore mostly-horizontal swipes (keeps page swipe working)
                            if abs(value.translation.height) > abs(value.translation.width) {
                                dragY = value.translation.height
                            }
                        }
                        .onEnded { value in
                            guard !isZoomed else { return }
                            let predicted = value.predictedEndTranslation.height
                            let shouldDismiss = abs(predicted) > dismissThreshold || abs(dragY) > dismissThreshold
                            if shouldDismiss {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    dragY = 0
                                }
                            }
                        }
                )
            }

            VStack(spacing: 0) {
                ZStack(alignment: .trailing) {
                    // top gradient scrim for button contrast
                    LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 100)
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea(edges: .top)

                    HStack(spacing: 8) {
                        Spacer()

                        if let alt = currentAltText, !alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            controlButton("text.alignleft", label: showAltText ? "Hide alt text" : "Show alt text") {
                                withAnimation(.snappy) { showAltText.toggle() }
                            }
                        }

                        Button {
                            showActions = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: UI.iconSize, weight: .semibold))
                                .frame(width: UI.controlSize, height: UI.controlSize)
                                .foregroundStyle(.white)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(radius: 1.5)
                        }
                        .accessibilityLabel("More options")

                        if isDownloading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: UI.controlSize, height: UI.controlSize)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(radius: 1.5)
                        }

                        controlButton("xmark", label: "Close") {
                            dismiss()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                Spacer()
            }
            .opacity(controlsOpacity)
            .animation(.easeInOut(duration: 0.18), value: isZoomed)
            .allowsHitTesting(!isZoomed)

            // Alt text overlay
            if showAltText {
                VStack {
                    Spacer()
                    AltTextOverlay(text: currentAltText)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea()
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog("Image options", isPresented: $showActions, titleVisibility: .visible) {
            Button("Download Image") {
                Task { await downloadCurrentImage() }
            }
            Button("Share Image") {
                Haptics.notify(.warning)
                alertTitle = "Not Implemented"
                alertMessage = "Sharing will be added soon."
                showAlert = true
            }
            .disabled(true)
            Button("Cancel", role: .cancel) { }
        }
    }

    @ViewBuilder
    private func controlButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: UI.iconSize, weight: .semibold))
                .frame(width: UI.controlSize, height: UI.controlSize)
                .foregroundStyle(.white)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(radius: 1.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var backgroundOpacity: Double {
        let progress = min(Double(abs(dragY)) / 400.0, 1.0)
        return max(0.3, 1 - progress)
    }

    private var dragShrink: CGFloat {
        let denom: CGFloat = 1000
        let limit: CGFloat = 0.1
        return min(abs(dragY) / denom, limit)
    }

    private var controlsOpacity: Double {
        let drag = 1 - min(Double(abs(dragY)) / 160.0, 1.0)
        return drag * (isZoomed ? 0.0 : 1.0)
    }

    private var currentAltText: String? {
        guard post.media.indices.contains(index) else { return nil }
        return post.media[index].altText
    }

    private var currentURL: URL? {
        guard post.media.indices.contains(index) else { return nil }
        return post.media[index].url
    }

    @MainActor
    private func downloadCurrentImage() async {
        guard let url = currentURL else {
            Haptics.notify(.error)
            alertTitle = "Save Failed"
            alertMessage = "Unable to determine image URL."
            showAlert = true
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { throw NSError(domain: "Image", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"]) }
            try await saveToPhotos(image)
            Haptics.notify(.success)
            alertTitle = "Saved"
            alertMessage = "Image saved to your Photos."
            showAlert = true
        } catch {
            Haptics.notify(.error)
            alertTitle = "Save Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func saveToPhotos(_ image: UIImage) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let finalStatus: PHAuthorizationStatus
        if status == .notDetermined {
            finalStatus = await requestPhotosAddOnlyAuthorization()
        } else {
            finalStatus = status
        }
        guard finalStatus == .authorized || finalStatus == .limited else {
            throw NSError(domain: "Photos", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos permission not granted."])
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, error in
                if let error = error { cont.resume(throwing: error) }
                else if success { cont.resume(returning: ()) }
                else { cont.resume(throwing: NSError(domain: "Photos", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown save error"])) }
            })
        }
    }

    private func requestPhotosAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                cont.resume(returning: status)
            }
        }
    }
}

struct ZoomableAsyncImage: View {
    let url: URL
    @Binding var isZoomed: Bool
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack { Color.black.opacity(0.1); ProgressView().tint(.white) }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                            .scaleEffect(scale)
                            .gesture(magnify)
                            .onTapGesture(count: 2) { withAnimation(.easeInOut) { toggleZoom() } }
                    case .failure:
                        ZStack { Color.black.opacity(0.1); Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.8)) }
                    @unknown default:
                        Color.black.opacity(0.1)
                    }
                }
                .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
            }
            // Allow TabView page swipe to work when not zoomed
            .scrollDisabled(!isZoomed)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black)
        }
    }

    private var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = clamp(lastScale * value)
                scale = newScale
                isZoomed = newScale > 1.01
            }
            .onEnded { _ in
                lastScale = clamp(scale)
                isZoomed = lastScale > 1.01
                withAnimation(.easeOut) { scale = lastScale }
            }
    }

    private func toggleZoom() {
        if scale > 1.2 {
            scale = 1; lastScale = 1; isZoomed = false
        } else {
            scale = 2; lastScale = 2; isZoomed = true
        }
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 1), 4) }
}

private struct AltTextOverlay: View {
    let text: String?

    var body: some View {
        VStack(spacing: 12) {
            // grabber
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 4)

            HStack {
                Text("Alt Text")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
            }

            ScrollView {
                Text(displayText)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.95))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(radius: 8)
    }

    private var displayText: String {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No alt text provided." : trimmed
    }
}
