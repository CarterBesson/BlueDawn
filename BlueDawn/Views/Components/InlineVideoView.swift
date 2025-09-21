import SwiftUI
import AVKit
import Combine

struct InlineVideoView: View {
    let url: URL
    @State private var player: AVPlayer? = nil
    @State private var isPlaying = false
    @State private var isMuted = true
    @State private var didInitMute = false
    @Environment(SessionStore.self) private var session
    private let pauseAll = Notification.Name("InlineVideoPauseAll")

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.isMuted = isMuted
                        if isPlaying { player.play() }
                    }
                    .onDisappear { player.pause() }
                    .disabled(true)
            } else {
                Rectangle().fill(Color.secondary.opacity(0.12))
            }

            Button(action: toggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }

            // Mute toggle
            VStack {
                HStack {
                    Button(action: toggleMute) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        }
        .onAppear {
            setupPlayerIfNeeded()
            if !didInitMute { isMuted = session.videoStartMuted; player?.isMuted = isMuted; didInitMute = true }
            if session.videoAutoplay, !isPlaying { isPlaying = true; player?.play() }
        }
        .onReceive(NotificationCenter.default.publisher(for: pauseAll)) { _ in
            pause()
        }
    }

    private func setupPlayerIfNeeded() {
        guard player == nil else { return }
        let p = AVPlayer(url: url)
        p.isMuted = true
        player = p
        // Loop playback
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            Task { @MainActor in
                if session.videoLoop {
                    p.seek(to: .zero)
                    if isPlaying { p.play() }
                } else {
                    pause()
                }
            }
        }
    }

    private func toggle() {
        guard let p = player else { return }
        isPlaying.toggle()
        if isPlaying { p.play() } else { p.pause() }
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    private func pause() {
        isPlaying = false
        player?.pause()
    }
}
