import Foundation
import Testing
@testable import LanternKit

private let gigabyte: Int64 = 1_073_741_824

@Test("S-075 a 16 GB Mac is offered Gemma 4 first")
func recommendsForSixteen() {
    #expect(ModelCatalog.recommended(totalMemory: 16 * gigabyte)?.name == "gemma4:e4b")
}

@Test("S-075 an 8 GB Mac is offered something that fits")
func recommendsForEight() {
    let pick = ModelCatalog.recommended(totalMemory: 8 * gigabyte)
    #expect(pick != nil)
    #expect(pick.map { ModelCatalog.fit($0, totalMemory: 8 * gigabyte) } == .good)
}

@Test("S-075 fit is honest about memory")
func ratesFit() {
    let gptOSS = ModelCatalog.models.first { $0.name == "gpt-oss:20b" }!
    #expect(ModelCatalog.fit(gptOSS, totalMemory: 16 * gigabyte) == .tooBig)
    #expect(ModelCatalog.fit(gptOSS, totalMemory: 32 * gigabyte) == .good)
}

@Test("S-075 an installed model isn't recommended again")
func skipsInstalled() {
    #expect(ModelCatalog.recommended(totalMemory: 16 * gigabyte, excluding: ["gemma4:e4b"])?.name != "gemma4:e4b")
    #expect(ModelCatalog.isInstalled("gemma4:e4b", in: ["gemma4:e4b"]))
    #expect(!ModelCatalog.isInstalled("gemma4:e4b", in: ["gemma4:e4b-mlx"]))
}

@Test("S-075 download progress adds up across parts, then finishes")
func decodesPull() throws {
    var decoder = PullDecoder()
    _ = try decoder.decode(#"{"status":"pulling manifest"}"#)
    _ = try decoder.decode(#"{"status":"pulling a1","digest":"a1","total":100,"completed":50}"#)
    let mid = try decoder.decode(#"{"status":"pulling b2","digest":"b2","total":300,"completed":0}"#)
    #expect(mid?.fraction == 50.0 / 400.0)
    #expect(mid?.step == "Downloading")
    let done = try decoder.decode(#"{"status":"success"}"#)
    #expect(done?.isDone == true && done?.fraction == 1)
}

@Test("S-075 a download error from Ollama is reported")
func reportsPullError() {
    var decoder = PullDecoder()
    #expect(throws: OllamaError.self) { try decoder.decode(#"{"error":"pull model manifest: file does not exist"}"#) }
}
