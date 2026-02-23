//
//  AudioService.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import AVFoundation
import AudioToolbox
import Combine

/// 音频播放服务
class AudioService: NSObject, ObservableObject {
    static let shared = AudioService()

    private var audioPlayer: AVAudioPlayer?
    private var soundEffectPlayer: AVAudioPlayer?  // 专门用于音效播放
    private var loadingTask: Task<Void, Never>?
    private var queueTask: Task<Void, Never>?
    private var playbackContinuation: CheckedContinuation<Void, Never>?

    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var playbackFailed = false

    private override init() {
        super.init()
        setupAudioSession()
    }

    /// 设置音频会话（统一配置，使用spokenAudio模式以获得更好的语音播放效果）
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            print("⚠️ [AudioService] 音频会话设置失败: \(error.localizedDescription)")
        }
    }

    /// 获取音频文件完整路径
    private func getAudioURL(for relativePath: String) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioURL = documentsPath.appendingPathComponent(relativePath)

        if FileManager.default.fileExists(atPath: audioURL.path) {
            return audioURL
        }
        return nil
    }

    /// 播放音频
    /// - Parameters:
    ///   - relativePath: 相对于Documents目录的路径
    ///   - timeout: 超时时间（秒）
    func play(relativePath: String?, timeout: TimeInterval = 3.0) {
        guard let path = relativePath, !path.isEmpty else {
            playbackFailed = true
            return
        }

        // 取消之前的加载任务和队列任务
        loadingTask?.cancel()
        queueTask?.cancel()
        stop()

        isLoading = true
        playbackFailed = false

        loadingTask = Task { @MainActor in
            // 使用超时机制
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !Task.isCancelled {
                    self.isLoading = false
                    self.playbackFailed = true
                }
            }

            guard let audioURL = self.getAudioURL(for: path) else {
                timeoutTask.cancel()
                self.isLoading = false
                self.playbackFailed = true
                return
            }

            do {
                timeoutTask.cancel()
                self.audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                self.audioPlayer?.delegate = self
                self.audioPlayer?.prepareToPlay()
                self.audioPlayer?.play()
                self.isLoading = false
                self.isPlaying = true
            } catch {
                timeoutTask.cancel()
                self.isLoading = false
                self.playbackFailed = true
            }
        }
    }

    /// 停止播放
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false

        // 安全地清理continuation（避免重复resume）
        if let continuation = playbackContinuation {
            playbackContinuation = nil
            continuation.resume()
        }
    }

    /// 取消队列播放任务
    func cancelQueue() {
        queueTask?.cancel()
        queueTask = nil
        loadingTask?.cancel()
        loadingTask = nil

        // 安全地清理continuation（避免重复resume）
        if let continuation = playbackContinuation {
            playbackContinuation = nil
            continuation.resume()
        }
    }

    /// 预加载音频
    func preload(relativePath: String?) {
        guard let path = relativePath, !path.isEmpty else { return }
        guard let audioURL = getAudioURL(for: path) else { return }

        Task {
            _ = try? AVAudioPlayer(contentsOf: audioURL)
        }
    }

    /// 播放回答正确的音效
    func playCorrectSound() {
        playBundleSound(named: "right")
    }

    /// 播放回答错误的音效
    func playWrongSound() {
        playBundleSound(named: "wrong")
    }

    /// 播放 Bundle 中的音频文件
    private func playBundleSound(named name: String) {
        // 尝试在 Resources 子目录中查找
        var soundURL = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Resources")

        // 如果找不到，尝试在根目录查找
        if soundURL == nil {
            soundURL = Bundle.main.url(forResource: name, withExtension: "wav")
        }

        guard let url = soundURL else {
            print("⚠️ [AudioService] 无法找到音频文件: \(name).wav")
            return
        }

        do {
            // 停止之前的音效播放
            soundEffectPlayer?.stop()

            // 创建新的播放器并保持引用
            soundEffectPlayer = try AVAudioPlayer(contentsOf: url)
            soundEffectPlayer?.prepareToPlay()
            soundEffectPlayer?.play()
        } catch {
            print("❌ [AudioService] 播放音效失败: \(error.localizedDescription)")
        }
    }

    /// 按顺序播放多个音频文件
    /// - Parameters:
    ///   - paths: 音频文件路径数组
    ///   - interval: 每个音频之间的间隔时间（秒）
    func playQueue(paths: [String?], interval: TimeInterval = 1.0) {
        // 取消之前的队列任务并停止播放
        cancelQueue()
        stop()

        queueTask = Task { @MainActor in
            for path in paths {
                // 检查任务是否被取消
                if Task.isCancelled {
                    break
                }

                guard let audioPath = path, !audioPath.isEmpty else {
                    continue
                }

                // 播放音频并等待完成
                await playAndWait(relativePath: audioPath)

                // 检查任务是否被取消
                if Task.isCancelled {
                    break
                }

                // 等待间隔时间
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// 播放音频并等待播放完成
    /// - Parameter relativePath: 相对于Documents目录的路径
    @MainActor
    private func playAndWait(relativePath: String) async {
        // 检查任务是否已取消
        guard !Task.isCancelled else { return }

        guard let audioURL = getAudioURL(for: relativePath) else {
            return
        }

        do {
            // 停止当前播放并安全地清理continuation
            audioPlayer?.stop()
            if let continuation = playbackContinuation {
                playbackContinuation = nil
                continuation.resume()
            }
            audioPlayer = nil

            // 创建并播放新的音频
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.delegate = self
            player.prepareToPlay()

            audioPlayer = player
            isPlaying = true
            playbackFailed = false

            player.play()

            // 使用Continuation等待播放完成
            await withCheckedContinuation { continuation in
                self.playbackContinuation = continuation
            }

        } catch {
            playbackFailed = true
        }
    }
}

extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            // 安全地恢复continuation（避免重复resume）
            if let continuation = self.playbackContinuation {
                self.playbackContinuation = nil
                continuation.resume()
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.playbackFailed = true
            // 安全地恢复continuation（避免重复resume）
            if let continuation = self.playbackContinuation {
                self.playbackContinuation = nil
                continuation.resume()
            }
        }
    }
}
