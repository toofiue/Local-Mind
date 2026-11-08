import AppKit
import SwiftUI
import LanternKit

/// One attached file: a thumbnail for an image, a chip for anything else.
struct AttachmentTile: View {
    let kind: AttachmentKind
    let fileName: String
    let imageData: Data?
    let pageCount: Int
    @State private var image: NSImage?

    var body: some View {
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
                .help(fileName)
                .accessibilityLabel(fileName)
            } else {
                HStack(spacing: Space.sm) {
                    Image(systemName: kind == .pdf ? "doc.richtext" : "doc.text")
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
                .padding(.horizontal, Space.md)
                .frame(height: Layout.thumbnail)
                .frame(maxWidth: Layout.chip)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: Radius.md))
                .help(fileName)
            }
        }
        .onAppear {
            if image == nil, let imageData { image = NSImage(data: imageData) }
        }
    }

    private var detail: LocalizedStringKey {
        kind == .pdf ? "^[\(pageCount) page](inflect: true)" : "Text"
    }
}

/// The attachments on the message being written.
struct DraftAttachmentRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.sm) {
                ForEach(model.draftAttachments) { item in
                    AttachmentTile(kind: item.kind, fileName: item.fileName, imageData: item.imageData, pageCount: item.pageCount)
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// The attachments on a sent message.
struct SentAttachmentRow: View {
    let message: Message

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(message.orderedAttachments) { item in
                AttachmentTile(kind: item.kind, fileName: item.fileName, imageData: item.imageData, pageCount: item.pageCount)
            }
        }
    }
}
