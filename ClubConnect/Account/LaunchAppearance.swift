import SwiftUI

struct LaunchAppearance: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showMark = false
    @State private var revealContent = false

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color("LaunchPaper")
            Image("ClubMark")
                .resizable()
                .scaledToFit()
                .frame(width: 94, height: 94)
                .scaleEffect(showMark ? 1 : 0.9)
                .opacity(showMark ? 1 : 0)
        }
        .ignoresSafeArea()
        .opacity(revealContent ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: reduceMotion) {
            guard !reduceMotion else { onFinished(); return }
            withAnimation(.easeOut(duration: 0.125)) { showMark = true }
            do {
                try await Task.sleep(for: .milliseconds(370))
                withAnimation(.easeInOut(duration: 0.18)) { revealContent = true }
                try await Task.sleep(for: .milliseconds(180))
                onFinished()
            } catch is CancellationError {
                // The presentation ended or Reduce Motion changed during launch.
            } catch {
                onFinished()
            }
        }
    }
}
