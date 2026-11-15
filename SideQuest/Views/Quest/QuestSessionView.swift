import SwiftUI

/// Full-screen container for one quest: card → photo → result.
struct QuestSessionView: View {
    @Environment(QuestFlowModel.self) private var flow
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Group {
                if flow.phase == .result {
                    ResultView()
                } else if flow.phase == .reviewing {
                    PhotoReviewView()
                } else if let active = flow.activeQuest {
                    QuestCardView(active: active)
                } else {
                    Color.clear
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: flow.phase == .result)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if flow.phase == .result { flow.finish() }
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .onChange(of: flow.phase) { _, phase in
            if phase == .idle { isPresented = false }
        }
        .onChange(of: flow.activeQuest == nil) { _, isNil in
            if isNil && flow.phase != .result { isPresented = false }
        }
    }
}
