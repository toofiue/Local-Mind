@preconcurrency import AVFoundation
import LanternKit
import Observation
@preconcurrency import Speech

/// Speaking to Local Mind: Apple's on-device speech recognition, the same engine as Mac dictation.
/// Words appear in the message box as you talk; nothing is sent until you press Send.
@Observable
final class Dictation {
    static let shared = Dictation()

    private(set) var isListening = false
    /// Why dictation can't start, when it can't.
    var problem: String?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?

    /// Starts listening. `onText` gets the words so far, each time they change.
    func start(onText: @escaping @MainActor (String) -> Void) {
        guard !isListening else { return }
        problem = nil
        Task {
            guard await Self.permitted() else {
                problem = "Allow Microphone and Speech Recognition for Local Mind in System Settings > Privacy & Security."
                return
            }
            begin(onText: onText)
        }
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
        isListening = false
    }

    private func begin(onText: @escaping @MainActor (String) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            problem = "Speech recognition isn't available for your language right now."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On this Mac only, when the language supports it. Nothing goes to a server.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.addsPunctuation = true

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.feeder(request))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            problem = "The microphone couldn't start."
            return
        }
        self.engine = engine
        self.request = request
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                if let text { onText(text) }
                if done { self?.stop() }
            }
        }
    }

    /// The audio tap runs on an audio thread, so it only hands buffers to the request.
    private nonisolated static func feeder(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private static func permitted() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// Reading a reply aloud with the Mac's own voices, the best one installed for your language.
@Observable
final class ReadAloud: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = ReadAloud()

    /// The reply being read, if any.
    private(set) var speakingID: UUID?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Reads the reply, or stops if it's already reading this one.
    func toggle(_ id: UUID, markdown: String) {
        if speakingID == id {
            stop()
            return
        }
        stop()
        let utterance = AVSpeechUtterance(string: ChatExport.speakable(markdown))
        utterance.voice = Self.bestVoice()
        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = nil
    }

    /// Premium voices sound most natural, then Enhanced, then the default.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String(language.prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        guard let best = voices.map(\.quality.rawValue).max() else { return AVSpeechSynthesisVoice(language: language) }
        let top = voices.filter { $0.quality.rawValue == best }
        return top.first { $0.language == language } ?? top.first
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
}
