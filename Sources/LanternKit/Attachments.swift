import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum AttachmentKind: String, Sendable {
    case image, pdf, text
}

/// A file read and ready to send with a message.
public struct LoadedAttachment: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: AttachmentKind
    public let fileName: String
    public let imageData: Data?
    public let text: String
    public let pageCount: Int

    public init(id: UUID = UUID(), kind: AttachmentKind, fileName: String, imageData: Data? = nil, text: String = "", pageCount: Int = 0) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.imageData = imageData
        self.text = text
        self.pageCount = pageCount
    }
}

public enum AttachmentError: Error, Equatable {
    case unsupported(String)
    case noReadableText(String)
}

/// How attached text goes into a message.
public enum AttachmentPrompt {
    public static func compose(message: String, files: [(name: String, text: String)]) -> String {
        let attached = files.map { "<file name=\"\($0.name)\">\n\($0.text)\n</file>" }
        return (attached + [message]).joined(separator: "\n\n")
    }

    /// Roughly four characters per token, which matched Gemma to within 1% on a long test document.
    public static func estimatedTokens(_ text: String) -> Int {
        (text.count + 3) / 4
    }

    public static func exceedsContext(_ text: String, limit: Int) -> Bool {
        estimatedTokens(text) > limit
    }
}

public enum AttachmentLoader {
    /// Images are shrunk to this many pixels on their longest side before sending.
    public static let maxImagePixels = 1_568

    public static func load(contentsOf url: URL) throws -> LoadedAttachment {
        guard let data = try? Data(contentsOf: url) else { throw AttachmentError.unsupported(url.lastPathComponent) }
        return try load(name: url.lastPathComponent, data: data)
    }

    public static func load(name: String, data: Data) throws -> LoadedAttachment {
        // Checked first because macOS can also open a PDF as an image.
        if data.starts(with: Data("%PDF".utf8)) { return try loadPDF(name: name, data: data) }
        if let image = normalizedImage(data) {
            return LoadedAttachment(kind: .image, fileName: name, imageData: image)
        }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw AttachmentError.unsupported(name)
        }
        guard !text.allSatisfy(\.isWhitespace) else { throw AttachmentError.noReadableText(name) }
        return LoadedAttachment(kind: .text, fileName: name, text: text)
    }

    private static func loadPDF(name: String, data: Data) throws -> LoadedAttachment {
        guard let document = PDFDocument(data: data) else { throw AttachmentError.unsupported(name) }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        let text = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AttachmentError.noReadableText(name) }
        return LoadedAttachment(kind: .pdf, fileName: name, text: text, pageCount: document.pageCount)
    }

    /// Re-encodes any image macOS can read as a JPEG, or a PNG if it has transparency.
    private static func normalizedImage(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxImagePixels,
              ] as CFDictionary) else { return nil }
        let hasAlpha = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(thumbnail.alphaInfo)
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
