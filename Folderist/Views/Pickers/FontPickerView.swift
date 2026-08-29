import AppKit
import SwiftUI

/// Font family list, face picker, live preview, and size control for a
/// style's `TextOverlay` (docs/FEATURES.md section 2, Text overlay; docs/research/ui-notes.md
/// "Text tab" / editor "Bottom bar" scale slider).
///
/// Family list comes from `NSFontManager.shared.availableFontFamilies`;
/// faces for the selected family come from `availableMembers(ofFontFamily:)`
/// (display names like "Regular" / "Bold" / "Condensed Bold"). The size
/// control is a slider from 8 to 500 plus an Auto-fit toggle that maps to
/// `TextOverlay.pointSize == nil`.
struct FontPickerView: View {
    @Binding var overlay: TextOverlay

    @State private var searchText: String = ""
    private let families: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        PickerPanel(title: "Font", searchText: $searchText, searchPlaceholder: "Search fonts") {
            HStack(spacing: 0) {
                familyList
                PickerDivider()
                VStack(spacing: 0) {
                    faceList
                    PickerDivider()
                    preview
                    PickerDivider()
                    sizeControls
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 440, height: 360)
    }

    // MARK: Family list

    private var filteredFamilies: [String] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return families }
        return families.filter { $0.lowercased().contains(q) }
    }

    private var familyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredFamilies, id: \.self) { family in
                    Button {
                        selectFamily(family)
                    } label: {
                        Text(family)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(family == overlay.fontFamily ? Color.accentColor.opacity(0.3) : Color.clear)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 180)
    }

    // MARK: Face list

    private var faces: [FontFace] {
        FontPickerView.faces(forFamily: overlay.fontFamily)
    }

    private var faceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(faces) { face in
                    Button {
                        overlay.fontFace = face.displayName
                    } label: {
                        Text(face.displayName)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(face.displayName == overlay.fontFace ? Color.accentColor.opacity(0.3) : Color.clear)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 110)
    }

    // MARK: Preview

    private var preview: some View {
        Text(overlay.text.isEmpty ? "Folder" : overlay.text)
            .font(previewFont)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.2)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 12)
    }

    private var previewFont: Font {
        let displaySize = min(overlay.pointSize ?? 96, 48)
        if let nsFont = FontPickerView.nsFont(family: overlay.fontFamily, face: overlay.fontFace, size: CGFloat(displaySize)) {
            return Font(nsFont)
        }
        return .system(size: displaySize)
    }

    // MARK: Size controls

    private var sizeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Auto-fit", isOn: Binding(
                get: { overlay.pointSize == nil },
                set: { isAutoFit in overlay.pointSize = isAutoFit ? nil : (overlay.pointSize ?? 96) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))

            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { overlay.pointSize ?? 96 },
                        set: { overlay.pointSize = $0 }
                    ),
                    in: 8...500
                )
                .disabled(overlay.pointSize == nil)
                Text(overlay.pointSize.map { "\(Int($0))" } ?? "Auto")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(10)
    }

    private func selectFamily(_ family: String) {
        overlay.fontFamily = family
        let newFaces = FontPickerView.faces(forFamily: family)
        if !newFaces.contains(where: { $0.displayName == overlay.fontFace }) {
            overlay.fontFace = newFaces.first?.displayName ?? "Regular"
        }
    }

    // MARK: NSFontManager bridging

    struct FontFace: Identifiable, Equatable {
        var displayName: String
        var postscriptName: String
        var id: String { postscriptName }
    }

    static func faces(forFamily family: String) -> [FontFace] {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family), !members.isEmpty else {
            return [FontFace(displayName: "Regular", postscriptName: family)]
        }
        let faces = members.compactMap { member -> FontFace? in
            guard member.count >= 2,
                  let postscriptName = member[0] as? String,
                  let displayName = member[1] as? String else { return nil }
            return FontFace(displayName: displayName, postscriptName: postscriptName)
        }
        return faces.isEmpty ? [FontFace(displayName: "Regular", postscriptName: family)] : faces
    }

    static func nsFont(family: String, face: String, size: CGFloat) -> NSFont? {
        if let match = faces(forFamily: family).first(where: { $0.displayName == face }),
           let font = NSFont(name: match.postscriptName, size: size) {
            return font
        }
        return NSFont(name: family, size: size)
            ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
    }
}
