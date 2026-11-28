import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MemberPortrait: View {
    @Environment(\.brandTheme) private var theme
    let name: String
    let imageData: Data?
    let diameter: CGFloat

    private var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let first = words.first?.first.map(String.init) ?? ""
        let last = words.count > 1 ? words.last?.first.map(String.init) ?? "" : ""
        return (first + last).uppercased()
    }

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    // A stable tint distinguishes initials even after an app relaunch.
                    let variant = name.utf8.reduce(0) { ($0 + Int($1)) % 5 }
                    Circle().fill(theme.wash)
                    Circle().fill(theme.accent.opacity(Double(variant) * 0.045))
                    if initials.isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: diameter * 0.38))
                    } else {
                        Text(initials)
                            .font(.system(size: diameter * 0.39, weight: .medium, design: .serif))
                    }
                }
                .foregroundStyle(theme.ink)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct CommunityMark: View {
    let logoData: Data?
    let side: CGFloat

    var body: some View {
        Group {
            if let logoData, let logo = UIImage(data: logoData) {
                Image(uiImage: logo).resizable()
            } else {
                ClubConnectMark()
            }
        }
        .scaledToFit()
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

struct AdaptivePhotoRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 18))
        layout { content() }
    }
}

struct CommunityPhotoPicker: View {
    let label: String
    let removalLabel: String
    @Binding var data: Data?
    @Binding var isLoading: Bool
    var preservesTransparency = false
    @State private var selected: PhotosPickerItem?
    @State private var problem: String?

    var body: some View {
        let pickerTitle = isLoading ? "Loading image…" : label
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $selected, matching: .images) {
                Label(pickerTitle, systemImage: "photo.on.rectangle")
            }
            if data != nil {
                Button(removalLabel, role: .destructive) {
                    selected = nil
                    data = nil
                }
                .disabled(isLoading)
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .task(id: selected) {
            guard let selected else {
                isLoading = false
                return
            }
            isLoading = true
            problem = nil
            do {
                guard let source = try await selected.loadTransferable(type: Data.self) else {
                    throw PhotoProblem.unreadable
                }
                let result = try await CommunityImageProcessor.prepare(source, preserveAlpha: preservesTransparency)
                try Task.checkCancellation()
                data = result
            } catch {
                guard !Task.isCancelled else { return }
                problem = "Couldn’t load this image. Try a different photo."
                self.selected = nil
            }
            if !Task.isCancelled { isLoading = false }
        }
    }
}

private enum PhotoProblem: Error { case unreadable }

private enum CommunityImageProcessor {
    // Store a display-size thumbnail and omit location and other source metadata.
    nonisolated static func prepare(_ bytes: Data, preserveAlpha: Bool) async throws -> Data {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else {
            throw PhotoProblem.unreadable
        }
        for side in [512, 384, 256, 192, 128] {
            try Task.checkCancellation()
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: side
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw PhotoProblem.unreadable
            }
            let output = NSMutableData()
            let alphaFormats: Set<CGImageAlphaInfo> = [.premultipliedFirst, .premultipliedLast, .first, .last, .alphaOnly]
            let format: UTType = preserveAlpha && alphaFormats.contains(image.alphaInfo) ? .png : .jpeg
            guard let destination = CGImageDestinationCreateWithData(output, format.identifier as CFString, 1, nil) else {
                throw PhotoProblem.unreadable
            }
            let settings = [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary
            CGImageDestinationAddImage(destination, image, settings)
            if CGImageDestinationFinalize(destination), output.length <= 110_000 {
                return output as Data
            }
        }
        throw PhotoProblem.unreadable
    }
}

extension String {
    var communityTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
