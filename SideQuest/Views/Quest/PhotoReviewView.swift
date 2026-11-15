import SwiftUI

/// Shown when people are in a shot: the exact (face-blurred) photos that would be sent.
/// Tap anything else to blur it too — name badges, screens, a face we missed.
struct PhotoReviewView: View {
    @Environment(QuestFlowModel.self) private var flow
    @State private var page = 0

    var body: some View {
        let pending = flow.pendingPhotos
        if !pending.isEmpty {
            ScrollView {
                VStack(spacing: 16) {
                    Text(summary(pending))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    TabView(selection: $page) {
                        ForEach(pending.indices, id: \.self) { index in
                            TappableBlurImage(image: pending[index].redacted) { point in
                                flow.addBlurSpot(at: point, photo: index)
                            }
                            .padding(.horizontal, 2)
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: pending.count > 1 ? .always : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(height: 440)

                    if pending.count > 1 {
                        Text("Photo \(min(page, pending.count - 1) + 1) of \(pending.count) — swipe to check each one.")
                            .font(.footnote.weight(.semibold))
                    }
                    Label("Tap anything else you'd like hidden, like a name badge or a screen.", systemImage: "hand.tap")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if pending.indices.contains(page), !pending[page].extraRegions.isEmpty {
                        Button("Undo last blur", systemImage: "arrow.uturn.backward") { flow.undoBlurSpot(photo: page) }
                            .font(.footnote.weight(.semibold))
                    }
                }
                .padding(20)
            }
            .background(Theme.softGradient.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    Button { flow.confirmReviewedPhoto() } label: {
                        Label(pending.count == 1 ? "Looks good, check it" : "Looks good, check them", systemImage: "checkmark.shield.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("sendReviewedPhoto")
                    Button { flow.cancelReview() } label: { Label("Retake", systemImage: "camera.rotate") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .bottomBar()
            }
            .navigationTitle("Check before sending")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func summary(_ pending: [QuestFlowModel.PendingPhoto]) -> String {
        let nothingSent = "Nothing has left your phone yet."
        let what = pending.count == 1 ? "This is exactly what gets sent." : "These are exactly what get sent."
        if pending.contains(where: \.detectionFailed) {
            return "We couldn't check \(pending.count == 1 ? "this photo" : "every photo") for faces automatically. Tap any face or name badge to blur it before sending. \(nothingSent)"
        }
        let faces = pending.reduce(0) { $0 + $1.faceCount }
        if faces > 0 {
            return "We blurred \(faces) face\(faces == 1 ? "" : "s") on your phone. \(what) \(nothingSent)"
        }
        if pending.contains(where: { $0.personCount > 0 }) {
            return "We spotted someone and blurred where their head is. Check nothing identifying is left before sending."
        }
        return "\(what) \(nothingSent)"
    }
}

/// An image that reports taps in normalised (0...1) coordinates.
private struct TappableBlurImage: View {
    var image: UIImage
    var onTap: (CGPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            let fitted = fittedSize(image.size, in: geometry.size)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    onTap(CGPoint(x: location.x / fitted.width, y: location.y / fitted.height))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Photo to be sent, with faces blurred. Tap a spot to blur it.")
        }
    }

    private func fittedSize(_ image: CGSize, in box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return box }
        let scale = min(box.width / image.width, box.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
