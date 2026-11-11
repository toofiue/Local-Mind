import AppKit
import QuickLook
import SwiftUI
import LanternKit

/// One attached file: a thumbnail for an image, a chip for anything else.
struct AttachmentTile: View {
    let kind: AttachmentKind
    let fileName: String
    let imageData: Data?
    let pageCount: Int
    var durationSeconds: Double = 0
    /// Opens a preview when clicked.
    var onPreview: (() -> Void)?
    /// Shows an X when the attachment can still be removed.
    var onRemove: (() -> Void)?
    @State private var image: NSImage?

    var body: some View {
        // A real button, so a click, the keyboard, and VoiceOver can all open the preview.
        Button { onPreview?() } label: { content }
            .buttonStyle(.plain)
            .disabled(onPreview == nil)
            .overlay(alignment: .topTrailing) {
                if let onRemove {
                    Button("Remove", systemImage: "xmark.circle.fill", action: onRemove)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                        // A backing keeps it visible on any picture.
                        .background(.regularMaterial, in: Circle())
                        .padding(Space.xs)
                        .help("Remove this attachment")
                        .accessibilityLabel("Remove \(fileName)")
                }
            }
            .onAppear {
                if image == nil, let imageData { image = NSImage(data: imageData) }
            }
    }

    private var content: some View {
        Group {
            if kind == .image {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.fill.tertiary)
                    }
                }
                .frame(width: Layout.thumbnail, height: Layout.thumbnail)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .help("\(fileName). Click to preview.")
                .accessibilityLabel(fileName)
            } else {
                HStack(spacing: Space.sm) {
                    Image(systemName: symbol)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, Space.md)
                .padding(.trailing, Space.xxl)
                .frame(height: Layout.thumbnail)
                .frame(maxWidth: Layout.chip)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: Radius.md))
                .help("\(fileName). Click to preview.")
            }
        }
        .contentShape(Rectangle())
    }

    private var symbol: String {
        switch kind {
        case .pdf: "doc.richtext"
        case .audio: "waveform"
        default: "doc.text"
        }
    }

    private var detail: LocalizedStringKey {
        switch kind {
        case .pdf: "^[\(pageCount) page](inflect: true)"
        case .audio: LocalizedStringKey(Duration.seconds(durationSeconds.rounded()).formatted(.time(pattern: .minuteSecond)))
        default: "Text"
        }
    }
}

/// The attachments on the message being written.
struct DraftAttachmentRow: View {
    @Environment(AppModel.self) private var model
    @State private var preview: URL?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.sm) {
                ForEach(model.draftAttachments) { item in
                    AttachmentTile(kind: item.kind, fileName: item.fileName, imageData: item.imageData, pageCount: item.pageCount,
                                   durationSeconds: item.durationSeconds,
                                   onPreview: {
                                       preview = AttachmentPreview.file(kind: item.kind, fileName: item.fileName, imageData: item.imageData,
                                                                        audioData: item.audioData, fileData: item.fileData, text: item.text)
                                   },
                                   onRemove: { model.removeAttachment(item.id) })
                }
            }
        }
        .scrollIndicators(.never)
        .quickLookPreview($preview)
    }
}

/// The attachments on a sent message.
struct SentAttachmentRow: View {
    let message: Message
    @State private var preview: URL?

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(message.orderedAttachments) { item in
                AttachmentTile(kind: item.kind, fileName: item.fileName, imageData: item.imageData, pageCount: item.pageCount,
                               durationSeconds: item.durationSeconds,
                               onPreview: {
                                   preview = AttachmentPreview.file(kind: item.kind, fileName: item.fileName, imageData: item.imageData,
                                                                    audioData: item.audioData, fileData: item.fileData, text: item.text)
                               })
            }
        }
        .quickLookPreview($preview)
    }
}
