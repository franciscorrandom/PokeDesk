import AVFoundation
import AppKit

@MainActor final class MigaVoice: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private let audioDirectory: URL?
    private(set) var lastPhrase = ""
    private(set) var submittedCount = 0
    var onSpeakingChanged: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    init(audioDirectory: URL? = nil) {
        self.audioDirectory = audioDirectory ?? Bundle.main.resourceURL?.appendingPathComponent("Voices", isDirectory: true)
        super.init()
    }

    func audioURL(_ clip: VoiceClip, voice: EnglishVoice) -> URL? {
        guard let directory = audioDirectory else { return nil }
        let actual = clip == .preview ? VoiceClip.meeting : clip
        let url = directory.appendingPathComponent("\(voice.rawValue)-\(actual.rawValue).mp3")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func missingClips(voice: EnglishVoice) -> [VoiceClip] {
        VoiceClip.allCases.filter { audioURL($0, voice: voice) == nil }
    }

    func speak(_ clip: VoiceClip, preferences: VoicePreferences) {
        guard preferences.enabled else { return }
        stop()
        let voice = preferences.selectedEnglishVoice
        guard let url = audioURL(clip, voice: voice) else {
            NSSound(named: "Glass")?.play()
            return
        }
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.delegate = self
            audio.volume = Float(min(1, max(0, preferences.volume)))
            audio.enableRate = false
            player = audio
            lastPhrase = clip.phrase
            submittedCount += 1
            guard audio.prepareToPlay(), audio.play() else {
                player = nil
                onError?("No pude iniciar el audio de \(voice.name). Comprueba la salida de sonido del Mac.")
                return
            }
            onSpeakingChanged?(true)
        } catch {
            player = nil
            onError?("No pude reproducir la grabación de \(voice.name): \(error.localizedDescription)")
        }
    }

    func stop() { player?.stop(); player = nil; onSpeakingChanged?(false) }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            self.onSpeakingChanged?(false)
            if !flag { self.onError?("La reproducción de voz se interrumpió.") }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            self.onSpeakingChanged?(false)
            self.onError?("No pude leer la grabación de voz. Vuelve a abrir la copia completa de PokeDesk.app.")
        }
    }
}
