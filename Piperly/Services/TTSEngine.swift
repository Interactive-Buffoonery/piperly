import AVFoundation
import Foundation
import sherpa_onnx

actor TTSEngine {
    private var tts: OpaquePointer?
    private var audioPlayer: AVAudioPlayer?
    private var sampleRate: Int32 = 24000
    private var isInitialized = false

    func initialize(modelDir: String) throws {
        guard !isInitialized else { return }

        let modelPath = (modelDir as NSString).appendingPathComponent("model.onnx")
        let voicesPath = (modelDir as NSString).appendingPathComponent("voices.bin")
        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")
        let dataDirPath = (modelDir as NSString).appendingPathComponent("espeak-ng-data")

        var kokoroConfig = SherpaOnnxOfflineTtsKokoroModelConfig()
        modelPath.withCString { model in
            voicesPath.withCString { voices in
                tokensPath.withCString { tokens in
                    dataDirPath.withCString { dataDir in
                        kokoroConfig.model = model
                        kokoroConfig.voices = voices
                        kokoroConfig.tokens = tokens
                        kokoroConfig.data_dir = dataDir
                        kokoroConfig.length_scale = 1.0
                    }
                }
            }
        }

        // We need to keep the strings alive for the duration of the C call.
        // Use a different approach with UnsafeMutablePointer.
        tts = createTTS(
            modelPath: modelPath,
            voicesPath: voicesPath,
            tokensPath: tokensPath,
            dataDirPath: dataDirPath
        )

        guard tts != nil else {
            throw TTSError.initializationFailed
        }

        sampleRate = SherpaOnnxOfflineTtsSampleRate(tts)
        isInitialized = true

        try configureAudioSession()
    }

    private func createTTS(
        modelPath: String,
        voicesPath: String,
        tokensPath: String,
        dataDirPath: String
    ) -> OpaquePointer? {
        let cModel = strdup(modelPath)
        let cVoices = strdup(voicesPath)
        let cTokens = strdup(tokensPath)
        let cDataDir = strdup(dataDirPath)
        let cProvider = strdup("cpu")
        let cEmpty = strdup("")
        defer {
            free(cModel)
            free(cVoices)
            free(cTokens)
            free(cDataDir)
            free(cProvider)
            free(cEmpty)
        }

        var kokoroConfig = SherpaOnnxOfflineTtsKokoroModelConfig(
            model: cModel,
            voices: cVoices,
            tokens: cTokens,
            data_dir: cDataDir,
            length_scale: 1.0,
            dict_dir: cEmpty,
            lexicon: cEmpty,
            lang: cEmpty
        )

        var vitsConfig = SherpaOnnxOfflineTtsVitsModelConfig(
            model: cEmpty,
            lexicon: cEmpty,
            tokens: cEmpty,
            data_dir: cEmpty,
            noise_scale: 0,
            noise_scale_w: 0,
            length_scale: 0,
            dict_dir: cEmpty
        )

        var matchaConfig = SherpaOnnxOfflineTtsMatchaModelConfig(
            acoustic_model: cEmpty,
            vocoder: cEmpty,
            lexicon: cEmpty,
            tokens: cEmpty,
            data_dir: cEmpty,
            noise_scale: 0,
            length_scale: 0,
            dict_dir: cEmpty
        )

        var kittenConfig = SherpaOnnxOfflineTtsKittenModelConfig(
            model: cEmpty,
            voices: cEmpty,
            tokens: cEmpty,
            data_dir: cEmpty,
            length_scale: 0
        )

        var zipvoiceConfig = SherpaOnnxOfflineTtsZipvoiceModelConfig(
            tokens: cEmpty,
            encoder: cEmpty,
            decoder: cEmpty,
            vocoder: cEmpty,
            data_dir: cEmpty,
            lexicon: cEmpty,
            feat_scale: 0,
            t_shift: 0,
            target_rms: 0,
            guidance_scale: 0
        )

        var modelConfig = SherpaOnnxOfflineTtsModelConfig(
            vits: vitsConfig,
            num_threads: 2,
            debug: 0,
            provider: cProvider,
            matcha: matchaConfig,
            kokoro: kokoroConfig,
            kitten: kittenConfig,
            zipvoice: zipvoiceConfig
        )

        var config = SherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            rule_fsts: cEmpty,
            max_num_sentences: 1,
            rule_fars: cEmpty,
            silence_scale: 1.0
        )

        return SherpaOnnxCreateOfflineTts(&config)
    }

    func speak(word: String, voiceID: Int, speed: Float) throws {
        guard let tts else {
            throw TTSError.notInitialized
        }

        // Stop any current playback
        audioPlayer?.stop()
        audioPlayer = nil

        let cText = strdup(word)
        defer { free(cText) }

        guard let audio = SherpaOnnxOfflineTtsGenerate(tts, cText, Int32(voiceID), speed) else {
            throw TTSError.generationFailed
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let sampleCount = Int(audio.pointee.n)
        guard sampleCount > 0 else { return }

        let wavData = samplesToWAV(
            samples: audio.pointee.samples,
            count: sampleCount,
            sampleRate: Int(audio.pointee.sample_rate)
        )

        audioPlayer = try AVAudioPlayer(data: wavData)
        audioPlayer?.play()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func configureAudioSession() throws {
        try AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.duckOthers]
        )
        try AVAudioSession.sharedInstance().setActive(true)
    }

    private func samplesToWAV(samples: UnsafePointer<Float>, count: Int, sampleRate: Int) -> Data {
        var data = Data()

        let bytesPerSample = 2
        let dataSize = count * bytesPerSample
        let fileSize = 44 + dataSize

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var chunkSize = UInt32(fileSize - 8)
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt sub-chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var subchunk1Size: UInt32 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1 // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var numChannels: UInt16 = 1
        data.append(Data(bytes: &numChannels, count: 2))
        var sampleRateVal: UInt32 = UInt32(sampleRate)
        data.append(Data(bytes: &sampleRateVal, count: 4))
        var byteRate: UInt32 = UInt32(sampleRate * bytesPerSample)
        data.append(Data(bytes: &byteRate, count: 4))
        var blockAlign: UInt16 = UInt16(bytesPerSample)
        data.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample: UInt16 = 16
        data.append(Data(bytes: &bitsPerSample, count: 2))

        // data sub-chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var subchunk2Size: UInt32 = UInt32(dataSize)
        data.append(Data(bytes: &subchunk2Size, count: 4))

        // Convert float samples to Int16
        for i in 0..<count {
            let clamped = max(-1.0, min(1.0, samples[i]))
            var sample = Int16(clamped * Float(Int16.max))
            data.append(Data(bytes: &sample, count: 2))
        }

        return data
    }

    func cleanup() {
        if let tts {
            SherpaOnnxDestroyOfflineTts(tts)
            self.tts = nil
        }
    }
}

enum TTSError: Error, LocalizedError {
    case initializationFailed
    case notInitialized
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed: "Failed to initialize TTS engine"
        case .notInitialized: "TTS engine not initialized"
        case .generationFailed: "Failed to generate speech"
        }
    }
}
