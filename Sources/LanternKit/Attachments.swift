import CoreGraphics
import Foundation
import ImageIO
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

public enum AttachmentLoader {
    /// Images are shrunk to this many pixels on their longest side before sending.
    public static let maxImagePixels = 1_568

    public static func load(contentsOf url: URL) throws -> LoadedAttachment {
        guard let data = try? Data(contentsOf: url) else { throw AttachmentError.unsupported(url.lastPathComponent) }
        return try load(name: url.lastPathComponent, data: data)
    }

    public static func load(name: String, data: Data) throws -> LoadedAttachment {
        if let image = normalizedImage(data) {
            return LoadedAttachment(kind: .image, fileName: name, imageData: image)
        }
        throw AttachmentError.unsupported(name)
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
