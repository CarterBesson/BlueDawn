import SwiftUI
import LinkPresentation
import Combine

@MainActor
final class LinkMetadataLoader: ObservableObject {
    @Published var metadata: LPLinkMetadata? = nil
    @Published var isLoading: Bool = false
    @Published var error: Error? = nil

    private let url: URL
    private var provider: LPMetadataProvider?
    private var isCancelled = false
    private static let cache = NSCache<NSURL, LPLinkMetadata>()

    init(url: URL) {
        self.url = url
        if let cached = Self.cache.object(forKey: url as NSURL) {
            self.metadata = cached
        } else {
            fetch()
        }
    }

    deinit {
        isCancelled = true
        provider?.cancel()
        provider = nil
    }

    func fetch() {
        isLoading = true
        error = nil

        let provider = LPMetadataProvider()
        self.provider = provider

        // Capture a stable flag by value so the completion can know if this
        // startFetching corresponds to the current active provider, without
        // capturing the provider reference itself.
        let isCurrent = { [weak self] () -> Bool in
            guard let self = self else { return false }
            return self.provider === provider
        }()

        let url = self.url
        provider.startFetchingMetadata(for: url) { meta, err in
            // Hop back to the main actor before touching any state.
            Task { @MainActor in
                guard !self.isCancelled else { return }

                // If this callback corresponds to the provider we started with, clear it.
                if isCurrent {
                    self.provider = nil
                }

                self.isLoading = false
                if let err {
                    self.error = err
                    return
                }
                if let meta {
                    Self.cache.setObject(meta, forKey: url as NSURL)
                    self.metadata = meta
                } else {
                    self.error = NSError(domain: "LinkMetadataLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No metadata"])
                }
            }
        }
    }
}

struct LPLinkViewWrapper: UIViewRepresentable {
    let metadata: LPLinkMetadata

    func makeUIView(context: Context) -> LPLinkView {
        let v = LPLinkView(metadata: metadata)
        v.accessibilityIgnoresInvertColors = true
        return v
    }

    func updateUIView(_ uiView: LPLinkView, context: Context) {
        uiView.metadata = metadata
    }
}

enum LinkPreviewStyle { case compact, card }
private let _linkPreviewImageCache = NSCache<NSString, UIImage>()

struct LinkPreviewView: View {
    let url: URL
    var onTap: ((URL) -> Void)? = nil
    var style: LinkPreviewStyle = .compact

    @Environment(\.openURL) private var openURL
    @StateObject private var loader: LinkMetadataLoader
    @State private var thumbnail: UIImage? = nil

    init(url: URL, style: LinkPreviewStyle = .compact, onTap: ((URL) -> Void)? = nil) {
        self.url = url
        self.onTap = onTap
        self.style = style
        _loader = StateObject(wrappedValue: LinkMetadataLoader(url: url))
    }

    private static func loadThumbnailIfNeeded(meta: LPLinkMetadata, url: URL, completion: @escaping (UIImage?) -> Void) {
        let cacheKey: NSString = (meta.url?.absoluteString ?? url.absoluteString) as NSString
        if let cached = _linkPreviewImageCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }
        let pickProvider = meta.imageProvider ?? meta.iconProvider
        guard let provider = pickProvider else {
            completion(nil)
            return
        }
        provider.loadObject(ofClass: UIImage.self) { obj, _ in
            let img = obj as? UIImage
            if let img {
                _linkPreviewImageCache.setObject(img, forKey: cacheKey)
            }
            DispatchQueue.main.async { completion(img) }
        }
    }

    private var fixedHeight: CGFloat {
        switch style {
        case .compact: return 96
        case .card:    return 160
        }
    }

    var body: some View {
        ZStack {
            if let meta = loader.metadata {
                switch style {
                case .compact:
                    compactRow(meta)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let onTap { onTap(url) } else { openURL(url) }
                        }
                        .onAppear { Self.loadThumbnailIfNeeded(meta: meta, url: url) { thumbnail = $0 } }
                        .onChange(of: loader.metadata?.url) { _, _ in
                            guard let meta = loader.metadata else { return }
                            Self.loadThumbnailIfNeeded(meta: meta, url: url) { thumbnail = $0 }
                        }
                case .card:
                    LPLinkViewWrapper(metadata: meta)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture {
                            if let onTap { onTap(url) } else { openURL(url) }
                        }
                }
            } else if loader.isLoading {
                skeleton
            } else {
                fallback
                    .onTapGesture {
                        if let onTap { onTap(url) } else { openURL(url) }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: fixedHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .redacted(reason: loader.isLoading ? .placeholder : [])
        .accessibilityLabel("Link preview: \(url.absoluteString)")
    }

    @ViewBuilder
    private func compactRow(_ meta: LPLinkMetadata) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Text stack
            VStack(alignment: .leading, spacing: 6) {
                Text(meta.originalURL?.host ?? meta.url?.host ?? url.host ?? "")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(meta.title ?? (meta.url?.absoluteString ?? url.absoluteString))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            // Thumbnail on the right
            Group {
                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay(Image(systemName: "photo").imageScale(.small).foregroundStyle(.secondary))
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 12)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)).frame(height: 16)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)).frame(height: 14)
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)).frame(height: 14)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var fallback: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "link")
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text(url.host ?? url.absoluteString)
                    .font(.headline)
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}
