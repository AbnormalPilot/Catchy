@preconcurrency import AVFoundation
import Speech

/// Live, on-device dictation with Apple's SpeechAnalyzer (macOS 26). Audio never leaves the Mac.
@Observable
final class VoiceListener {
    enum VoiceError: LocalizedError {
        case microphoneDenied, unsupportedLanguage

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "Catchy needs microphone access to hear you. Turn it on in System Settings › Privacy & Security › Microphone."
            case .unsupportedLanguage: "On-device dictation isn't available for this Mac's language yet."
            }
        }
    }

    /// Everything heard so far: settled words plus the words still being worked out.
    private(set) var transcript = ""
    /// 0…1 microphone level, for the waveform.
    private(set) var level: Float = 0
    /// When the words last changed, for stopping after a pause.
    private(set) var lastHeard = Date.now

    private var settled = ""
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var feed: AudioFeed?
    private var results: Task<Void, Never>?

    func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw VoiceError.microphoneDenied }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw VoiceError.unsupportedLanguage
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        // The language model is a one-time download, handled by the system.
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()
        }

        settled = ""
        transcript = ""
        lastHeard = .now
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let words = String(result.text.characters)
                    guard let self else { return }
                    if result.isFinal {
                        self.settled += words
                        self.transcript = self.settled
                    } else {
                        self.transcript = self.settled + words
                    }
                    self.lastHeard = .now
                }
            } catch {}
        }
        try await analyzer.start(inputSequence: stream)

        let input = engine.inputNode
        let feed = AudioFeed(from: input.outputFormat(forBus: 0), to: format, continuation: continuation) { [weak self] level in
            Task { @MainActor in self?.level = level }
        }
        self.feed = feed
        feed.install(on: input)
        engine.prepare()
        try engine.start()
    }

    /// Stops listening and returns what was said.
    func finish() async -> String {
        stopAudio()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
        analyzer = nil
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        stopAudio()
        results?.cancel()
        let analyzer = self.analyzer
        self.analyzer = nil
        Task { await analyzer?.cancelAndFinishNow() }
    }

    private func stopAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        feed?.finish()
        feed = nil
        level = 0
    }
}

/// Converts microphone buffers to the analyzer's format and feeds them in. Runs on the
/// real-time audio thread, so it stays off the main actor.
nonisolated private final class AudioFeed: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let format: AVAudioFormat?
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let onLevel: @Sendable (Float) -> Void

    init(from input: AVAudioFormat, to format: AVAudioFormat?, continuation: AsyncStream<AnalyzerInput>.Continuation,
         onLevel: @escaping @Sendable (Float) -> Void) {
        self.format = format
        self.converter = format.flatMap { $0 == input ? nil : AVAudioConverter(from: input, to: $0) }
        self.continuation = continuation
        self.onLevel = onLevel
    }

    func install(on node: AVAudioInputNode) {
        node.installTap(onBus: 0, bufferSize: 4096, format: node.outputFormat(forBus: 0)) { [self] buffer, _ in
            onLevel(Self.level(of: buffer))
            continuation.yield(AnalyzerInput(buffer: convert(buffer) ?? buffer))
        }
    }

    func finish() {
        continuation.finish()
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter, let format else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        // The converter calls this block synchronously, inside convert(); nothing runs concurrently.
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let source = buffer
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return source
        }
        return error == nil ? output : nil
    }

    /// Rough loudness (RMS) mapped to 0…1.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 50) / 40))
    }
}
