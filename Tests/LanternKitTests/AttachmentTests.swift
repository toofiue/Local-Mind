import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LanternKit

func makeImage(width: Int, height: Int, type: UTType = .png) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func pixelSize(_ data: Data) -> (Int, Int) {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    return (properties[kCGImagePropertyPixelWidth] as! Int, properties[kCGImagePropertyPixelHeight] as! Int)
}

@Test("S-016 an image file loads as an image")
func loadsImage() throws {
    let attachment = try AttachmentLoader.load(name: "shot.png", data: makeImage(width: 100, height: 50))
    #expect(attachment.kind == .image)
    #expect(attachment.fileName == "shot.png")
    #expect(attachment.imageData != nil)
}

@Test("S-016 large images shrink, keeping their shape")
func shrinksLargeImages() throws {
    let attachment = try AttachmentLoader.load(name: "big.jpg", data: makeImage(width: 4_000, height: 2_000, type: .jpeg))
    let (width, height) = pixelSize(try #require(attachment.imageData))
    #expect(width == AttachmentLoader.maxImagePixels)
    #expect(height == AttachmentLoader.maxImagePixels / 2)
}

@Test("S-016 small images keep their size")
func keepsSmallImages() throws {
    let attachment = try AttachmentLoader.load(name: "small.png", data: makeImage(width: 64, height: 48))
    let (width, height) = pixelSize(try #require(attachment.imageData))
    #expect(width == 64 && height == 48)
}

@Test("S-016 images go in the request as base64")
func sendsImages() async throws {
    let transport = ScriptedTransport(installed: [])
    transport.script(ScriptedTransport.reply(text: ["ok"]))
    let turns = [ChatTurn(role: "user", content: "what is this", images: ["QUJD"])]
    for try await _ in OllamaClient(transport: transport).chat(model: "m", turns: turns, think: false) {}
    #expect(transport.chatBodies[0].contains("\"images\":[\"QUJD\"]"))
}

@Test("S-016 a message with no images has no images field")
func omitsImages() async throws {
    let transport = ScriptedTransport(installed: [])
    transport.script(ScriptedTransport.reply(text: ["ok"]))
    for try await _ in OllamaClient(transport: transport).chat(model: "m", turns: [ChatTurn(role: "user", content: "hi")], think: false) {}
    #expect(!transport.chatBodies[0].contains("images"))
}
