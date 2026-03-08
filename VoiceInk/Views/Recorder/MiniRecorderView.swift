import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService

    @State private var activePopover: ActivePopoverState = .none

    // MARK: - Design Constants
    private let mainContentHeight: CGFloat = 40
    private let width: CGFloat = 184
    private let cornerRadius: CGFloat = 20

    private var contentLayout: some View {
        HStack(spacing: 0) {
            RecorderPromptButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.leading, 12)

            Spacer(minLength: 0)

            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeter: recorder.audioMeter
            )

            Spacer(minLength: 0)

            RecorderPowerModeButton(
                activePopover: $activePopover,
                buttonSize: 22,
                padding: EdgeInsets()
            )
            .padding(.trailing, 12)
        }
        .frame(height: mainContentHeight)
    }

    private var partialTranscriptSection: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { _ in
            let hasText = stateProvider.recordingState == .recording && !stateProvider.partialTranscript.isEmpty

            VStack(spacing: 0) {
                if hasText {
                    Divider()
                        .background(Color.white.opacity(0.15))

                    Text(stateProvider.partialTranscript)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: hasText)
        }
    }

    var body: some View {
        if windowManager.isVisible {
            VStack(spacing: 0) {
                contentLayout
                partialTranscriptSection
            }
            .frame(width: width)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
