import SwiftUI
import UIKit

/// In-app camera only (`UIImagePickerController` with `.camera`). Library photos are never accepted.
struct CameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Only the pixels are used; `info[.mediaMetadata]` (EXIF etc.) is deliberately ignored.
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// Bundled sample photos for the simulator, which has no camera. Debug builds only — the
/// images are excluded from Release builds.
struct TestPhotoPicker: View {
    var onPick: (UIImage, Verdict.Outcome) -> Void

    struct Sample: Identifiable {
        var id: String { file }
        var file: String
        var title: String
        var outcome: Verdict.Outcome
    }

    static let samples: [Sample] = [
        Sample(file: "debug_test_pass.jpg", title: "Should pass", outcome: .pass),
        Sample(file: "debug_test_unsure.jpg", title: "Should be unsure", outcome: .unsure),
        Sample(file: "debug_test_fail.jpg", title: "Should fail", outcome: .fail),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Debug: use a test photo").font(.headline)
            Text("No camera here (simulator), so pick a bundled photo. In demo mode the verdict follows the label; with Claude the real model judges it.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(Self.samples) { sample in
                    if let image = UIImage(named: sample.file) {
                        Button { onPick(image, sample.outcome) } label: {
                            VStack(spacing: 6) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(sample.title).font(.caption.weight(.semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("testPhoto-\(sample.outcome.rawValue)")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            if Self.samples.allSatisfy({ UIImage(named: $0.file) == nil }) {
                Text("Test photos aren't bundled in this build.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}
