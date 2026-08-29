import AppKit
import SwiftUI

/// The editor's **Image** tab (fm5): the current image, a way to swap it, and
/// the four FolderMarker compositing modes — Fill, Over, Stamp, Only.
struct EditorImageTab: View {
    @EnvironmentObject private var assetStore: AssetStore
    @Binding var draft: Style
    @State private var isDropTargeted = false

    private var current: (fileName: String, mode: ImageMode)? {
        if case .image(let fileName, let mode) = draft.graphic { return (fileName, mode) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 8) {
                    Text(current?.fileName ?? "No image")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Button(current == nil ? "Add Image…" : "Change Image…") { chooseImage() }
                        .font(.system(size: 12))
                    Text("or drag an image or .icns file here")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            Text("Mode")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("", selection: modeBinding) {
                Text("Fill").tag(ImageMode.fill)
                Text("Over").tag(ImageMode.over)
                Text("Stamp").tag(ImageMode.stamp)
                Text("Only").tag(ImageMode.only)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(current == nil)

            Text(modeExplanation)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            // "Remove Icon" clears the image here, and every other content
            // tab offers the same pair (#16).
            OverlayRemoveButtons(draft: $draft)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            FolderDropResolver.resolveFiles(providers) { urls in
                importDroppedFile(urls)
            }
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    /// Uses the first droppable file as the style's image: `.icns` contributes
    /// its largest representation, other readable images are copied as-is.
    private func importDroppedFile(_ urls: [URL]) {
        for url in urls {
            do {
                let fileName: String
                if url.pathExtension.lowercased() == "icns" {
                    guard let data = StyleActions.pngData(fromIconFile: url) else { continue }
                    fileName = try assetStore.storeImageData(data, preferredExtension: "png")
                } else if StyleActions.isImageFile(url) {
                    fileName = try assetStore.importImage(from: url)
                } else {
                    continue
                }
                draft.graphic = .image(fileName: fileName, mode: current?.mode ?? .over)
                return
            } catch {
                StyleActions.report(error, title: "Couldn't import “\(url.lastPathComponent)”")
                return
            }
        }
        NSSound.beep()
    }

    private var thumbnail: some View {
        Group {
            if let fileName = current?.fileName,
               let image = AppServices.shared.renderResources.userImage(named: fileName) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 96, height: 96)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }

    private var modeBinding: Binding<ImageMode> {
        Binding(
            get: { current?.mode ?? .over },
            set: { newMode in
                guard let fileName = current?.fileName else { return }
                draft.graphic = .image(fileName: fileName, mode: newMode)
            }
        )
    }

    private var modeExplanation: String {
        switch current?.mode ?? .over {
        case .fill: return "The image fills the folder's front panel, clipped to its shape."
        case .over: return "The image is composited on top of the folder icon."
        case .stamp: return "A black & white image engraved into the folder color."
        case .only: return "The image replaces the folder icon entirely."
        }
    }

    private func chooseImage() {
        guard let url = StyleActions.chooseImage() else { return }
        do {
            let fileName = try assetStore.importImage(from: url)
            draft.graphic = .image(fileName: fileName, mode: current?.mode ?? .over)
        } catch {
            StyleActions.report(error, title: "Couldn't import that image")
        }
    }
}
