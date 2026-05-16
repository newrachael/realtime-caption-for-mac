import SwiftUI

struct SubtitleOverlayView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let primaryText = viewModel.translatedText.isEmpty ? viewModel.sourceText : viewModel.translatedText
        let shouldShowSource = !viewModel.sourceText.isEmpty && !viewModel.translatedText.isEmpty

        VStack(spacing: 10) {
            if !primaryText.isEmpty {
                captionScrollView(primaryText)
            } else if viewModel.state != .running {
                Text("Realtime Caption for Mac")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                Color.clear.frame(height: max(32, viewModel.overlayFontSize))
            }

            if shouldShowSource {
                Text(viewModel.sourceText)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.white.opacity(0.72))
            }

            if viewModel.state == .running || viewModel.state == .connecting {
                diagnosticsStrip
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(viewModel.overlayOpacity))
        )
    }

    private func captionScrollView(_ text: String) -> some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(size: viewModel.overlayFontSize, weight: .semibold, design: .default))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.82)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 5, x: 0, y: 2)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diagnosticsStrip: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                    Capsule()
                        .fill(viewModel.audioLevel > 0.04 ? .green.opacity(0.9) : .orange.opacity(0.8))
                        .frame(width: max(4, proxy.size.width * viewModel.audioLevel))
                }
            }
            .frame(width: 80, height: 6)

            Text("Audio \(Int(viewModel.audioLevel * 100))%")
            Text("Events \(viewModel.realtimeEventCount)")
            Text(viewModel.lastRealtimeEvent.components(separatedBy: " | ").first ?? viewModel.lastRealtimeEvent)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity)
    }
}
