import CoreGraphics
import CoreText
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

func makePDF(pages: [String]) -> Data {
    let output = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 300, height: 300)
    let context = CGContext(consumer: CGDataConsumer(data: output)!, mediaBox: &box, nil)!
    for text in pages {
        context.beginPDFPage(nil)
        if !text.isEmpty {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 12, nil),
            ]))
            context.textPosition = CGPoint(x: 20, y: 200)
            CTLineDraw(line, context)
        }
        context.endPDFPage()
    }
    context.closePDF()
    return output as Data
}

@Test("S-017 PDF text and page count are read")
func readsPDF() throws {
    let attachment = try AttachmentLoader.load(name: "report.pdf", data: makePDF(pages: ["First page text", "Second page text"]))
    #expect(attachment.kind == .pdf)
    #expect(attachment.pageCount == 2)
    #expect(attachment.text.contains("First page text"))
    #expect(attachment.text.contains("Second page text"))
}

@Test("S-017 a PDF with no text layer is refused")
func refusesBlankPDF() {
    #expect(throws: AttachmentError.noReadableText("scan.pdf")) {
        try AttachmentLoader.load(name: "scan.pdf", data: makePDF(pages: ["", ""]))
    }
}

@Test("S-017 attached text goes in the prompt with its file name")
func composesPrompt() {
    let prompt = AttachmentPrompt.compose(message: "Summarize this", files: [(name: "report.pdf", text: "Revenue rose.")])
    #expect(prompt == "<file name=\"report.pdf\">\nRevenue rose.\n</file>\n\nSummarize this")
}

@Test("S-017 a message with no files is unchanged")
func composesPlainPrompt() {
    #expect(AttachmentPrompt.compose(message: "Hello", files: []) == "Hello")
}

@Test("S-017 text over the model's limit is flagged", arguments: [(39_000, false), (41_000, true)])
func flagsLongText(characters: Int, flagged: Bool) {
    #expect(AttachmentPrompt.exceedsContext(String(repeating: "a", count: characters), limit: 10_000) == flagged)
}

@Test("S-017 MLX models use their full limit from Ollama")
func readsContextLimit() async throws {
    let installed = OllamaModel(name: "m", size: 1, contextLimit: 262_144)
    let models = try await OllamaClient(transport: ScriptedTransport(installed: [installed])).models()
    #expect(models[0].contextLimit == 262_144)
}

@Test("S-018 a UTF-8 file is read as text")
func readsText() throws {
    let attachment = try AttachmentLoader.load(name: "main.swift", data: Data("print(\"héllo\")\n".utf8))
    #expect(attachment.kind == .text)
    #expect(attachment.text == "print(\"héllo\")\n")
}

@Test("S-018 binary files are refused", arguments: [Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]), Data([0xFF, 0xFE, 0xFD])])
func refusesBinary(data: Data) {
    #expect(throws: AttachmentError.unsupported("app.zip")) {
        try AttachmentLoader.load(name: "app.zip", data: data)
    }
}

@Test("S-018 an empty file has no readable text")
func refusesEmpty() {
    #expect(throws: AttachmentError.noReadableText("empty.txt")) {
        try AttachmentLoader.load(name: "empty.txt", data: Data("  \n".utf8))
    }
}

@Test("S-020 only vision models accept images")
func readsVision() {
    #expect(OllamaModel(name: "a", size: 1, capabilities: ["completion", "vision"]).supportsImages)
    #expect(!OllamaModel(name: "b", size: 1, capabilities: ["completion"]).supportsImages)
}
