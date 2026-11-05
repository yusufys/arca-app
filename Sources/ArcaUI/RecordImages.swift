import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import ArcaCore
import ArcaPersistence
#if os(iOS)
import PhotosUI
#endif

/// Bounded decoding avoids loading a full camera image into every record row.
/// Re-encoding pixels also discards EXIF/GPS metadata rather than syncing it accidentally.
enum RecordImageCodec {
    static func thumbnail(_ data: Data, pixels: Int) throws -> CGImage {
        guard !data.isEmpty, data.count <= 15 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source), UTType(type as String)?.conforms(to: .image) == true,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CollectionIconImageError.invalidImageData }
        return image
    }

    static func prepare(_ data: Data) throws -> Data {
        guard data.count <= 15 * 1024 * 1024 else { throw CollectionIconImageError.fileTooLarge }
        let image = try thumbnail(data, pixels: 2048)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CollectionIconImageError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 5 * 1024 * 1024 else {
            throw CollectionIconImageError.encodingFailed
        }
        return output as Data
    }
}

@available(macOS 14.0, iOS 17.0, *)
struct StoredRecordImage: View {
    let viewModel: ArcaAppViewModel
    let spaceId: UUID
    let reference: AttachmentReference
    let size: CGFloat
    var cropped = false
    @ViewState private var pixels: CGImage?
    @ViewState private var failed = false

    var body: some View {
        Group {
            if let pixels {
                Image(decorative: pixels, scale: 1).resizable().aspectRatio(contentMode: cropped ? .fill : .fit)
            } else {
                ZStack {
                    Color.secondary.opacity(0.1)
                    Image(systemName: failed ? "photo.badge.exclamationmark" : "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.language.localized(failed ? "Image unavailable. Try syncing again." : "Record image"))
        .task(id: reference.sha256Hex) {
            pixels = nil
            failed = false
            do {
                let data = try await viewModel.imageData(reference, spaceId: spaceId)
                let decoded = try await Task.detached(priority: .utility) {
                    try RecordImageCodec.thumbnail(data, pixels: Int(size * 3))
                }.value
                try Task.checkCancellation()
                pixels = decoded
            } catch is CancellationError { } catch { failed = true }
        }
    }
}

@available(macOS 14.0, iOS 17.0, *)
struct RecordThumbnail: View {
    let viewModel: ArcaAppViewModel
    let record: RecordItem
    let schema: CollectionSchema
    var size: CGFloat = 48
    private let presentation = CollectionPresentationStore.shared

    var body: some View {
        if let reference = presentation.thumbnailReference(for: record, schema: schema) {
            StoredRecordImage(viewModel: viewModel, spaceId: record.spaceId, reference: reference, size: size, cropped: true)
                .accessibilityHidden(true)
        }
    }
}

@available(macOS 14.0, iOS 17.0, *)
struct ImageFieldEditor: View {
    let viewModel: ArcaAppViewModel
    let spaceId: UUID
    let field: FieldDefinition
    @Binding var value: FieldValue
    let chooseFile: () -> Void
    let importingChanged: (Bool) -> Void
    @ViewState private var error: String?
    @ViewState private var importing = false
    #if os(iOS)
    @ViewState private var selectedPhoto: PhotosPickerItem?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .attachments(let images) = value, let image = images.first {
                StoredRecordImage(viewModel: viewModel, spaceId: spaceId, reference: image, size: 120)
                Button(role: .destructive) { value = .null } label: {
                    Label(viewModel.language.localized("Remove image"), systemImage: "trash")
                        .frame(minHeight: 44)
                }
                .accessibilityLabel(viewModel.language.format("Remove image from %@", field.label))
            }
            #if os(iOS)
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(viewModel.language.localized("Choose from Photos"), systemImage: "photo.on.rectangle")
                    .frame(minHeight: 44)
            }
            .disabled(importing)
            .onChange(of: selectedPhoto) { _, selection in
                guard let selection else { return }
                importing = true
                importingChanged(true)
                Task {
                    defer { importing = false; selectedPhoto = nil; importingChanged(false) }
                    do {
                        // FileRepresentation keeps large originals out of memory until the size check.
                        guard let file = try await selection.loadTransferable(type: PickedRecordPhoto.self) else {
                            throw CollectionIconImageError.invalidImageData
                        }
                        defer { try? FileManager.default.removeItem(at: file.url) }
                        let ref = try await viewModel.attachImage(from: file.url, to: spaceId)
                        value = .attachments([ref])
                    } catch { self.error = viewModel.language.localized(error.localizedDescription) }
                }
            }
            #endif
            Button(action: chooseFile) {
                Label(viewModel.language.localized("Choose Image from Files"), systemImage: "folder")
                    .frame(minHeight: 44)
            }
            .disabled(importing)
            if importing { ProgressView() }
            Text(viewModel.language.localized("One image per field. Add more Image fields for more photos."))
                .arcaFont(.footnote).foregroundStyle(.secondary)
        }
        .alert(viewModel.language.localized("Image could not be added"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(viewModel.language.localized("OK")) { error = nil }
        } message: { Text(error ?? "") }
    }
}

#if os(iOS)
private struct PickedRecordPhoto: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 15 * 1024 * 1024 else { throw CollectionIconImageError.fileTooLarge }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".image")
            try FileManager.default.copyItem(at: received.file, to: copy)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: copy.path)
            return PickedRecordPhoto(url: copy)
        }
    }
}
#endif
