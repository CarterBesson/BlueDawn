import SwiftUI

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
    private let dismissThreshold: CGFloat = 140
    @Environment(\.dismiss) private var dismiss

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
                // Reset zoom state when changing pages so gestures behave predictably
                .onChange(of: index) { _, _ in
                    isZoomed = false
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

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 2)
                    }
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
            .opacity(1 - min(Double(abs(dragY)) / 160.0, 1.0))
        }
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
