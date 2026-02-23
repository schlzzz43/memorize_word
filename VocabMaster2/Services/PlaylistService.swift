//
//  PlaylistService.swift
//  VocabMaster2
//
//  Created on 2026/01/28.
//

import Foundation
import SwiftUI
import AVFoundation
import Combine
import MediaPlayer


/// 播放内容类型
enum PlaybackContent: String, CaseIterable {
    case wordOnly = "仅单词"
    case exampleOnly = "仅例句"
    case wordAndExample = "单词+例句"
}

/// 播放顺序
enum PlaybackOrder: String, CaseIterable {
    case sequential = "正序"
    case reverse = "逆序"
    case random = "随机"
}

/// 播放状态
enum PlaybackState {
    case idle
    case playing
    case paused
}

/// 播放列表服务
class PlaylistService: NSObject, ObservableObject {
    static let shared = PlaylistService()

    @Published var playbackState: PlaybackState = .idle
    @Published var currentWordIndex: Int = 0
    @Published var currentWord: Word?
    @Published var playbackContent: PlaybackContent = .wordAndExample
    @Published var playbackOrder: PlaybackOrder = .sequential
    @Published var backgroundPlaybackEnabled: Bool = true
    @Published var autoPlayNext: Bool = true

    var playlist: [Word] = []
    private var originalPlaylist: [Word] = []  // 保存原始播放列表
    private var audioPlayer: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?
    private var playbackContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        // 不在这里设置音频会话，由AudioService统一管理
        setupRemoteCommands()
    }

    /// 设置远程控制命令（锁屏控制）
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // 播放命令
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.play()
            }
            return .success
        }

        // 暂停命令
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }

        // 下一首命令
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.next()
            }
            return .success
        }

        // 上一首命令
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.previous()
            }
            return .success
        }
    }

    /// 更新锁屏播放信息
    @MainActor
    private func updateNowPlayingInfo() {
        guard let word = currentWord else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = word.word
        nowPlayingInfo[MPMediaItemPropertyArtist] = word.meaning
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "VocabMaster"
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackState == .playing ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        // 设置播放进度
        if !playlist.isEmpty {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentWordIndex)
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(playlist.count)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    /// 加载播放列表
    @MainActor
    func loadPlaylist(_ words: [Word]) {
        // 先停止当前播放
        stop()

        // 保存原始列表
        originalPlaylist = words

        // 根据播放顺序处理列表
        switch playbackOrder {
        case .sequential:
            playlist = words
        case .reverse:
            playlist = Array(words.reversed())
        case .random:
            playlist = words.enhancedShuffled()
        }

        currentWordIndex = 0
        if !playlist.isEmpty {
            currentWord = playlist[0]
        }
    }

    /// 重新应用播放顺序（用于切换播放顺序时）
    @MainActor
    func reapplyPlaybackOrder() {
        loadPlaylist(originalPlaylist)
    }

    /// 播放
    @MainActor
    func play() {
        guard !playlist.isEmpty else { return }

        if playbackState == .paused {
            // 如果是暂停状态，继续播放当前音频
            audioPlayer?.play()
            playbackState = .playing
            updateNowPlayingInfo()
        } else {
            // 开始播放
            playbackState = .playing
            updateNowPlayingInfo()
            startPlayback()
        }
    }

    /// 暂停
    @MainActor
    func pause() {
        audioPlayer?.pause()
        playbackState = .paused
        updateNowPlayingInfo()
    }

    /// 停止
    @MainActor
    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        playbackState = .idle
        currentWordIndex = 0

        // 安全地清理continuation（避免重复resume）
        if let continuation = playbackContinuation {
            playbackContinuation = nil
            continuation.resume()
        }

        // 清空播放列表
        playlist = []
        originalPlaylist = []
        currentWord = nil
        updateNowPlayingInfo()
    }

    /// 下一个
    @MainActor
    func next() {
        if currentWordIndex < playlist.count - 1 {
            currentWordIndex += 1
            currentWord = playlist[currentWordIndex]
            updateNowPlayingInfo()

            if playbackState == .playing {
                // 如果正在播放，继续播放下一个
                playbackTask?.cancel()
                startPlayback()
            }
        }
    }

    /// 上一个
    @MainActor
    func previous() {
        if currentWordIndex > 0 {
            currentWordIndex -= 1
            currentWord = playlist[currentWordIndex]
            updateNowPlayingInfo()

            if playbackState == .playing {
                // 如果正在播放，继续播放上一个
                playbackTask?.cancel()
                startPlayback()
            }
        }
    }

    /// 跳到第一个
    @MainActor
    func skipToFirst() {
        currentWordIndex = 0
        currentWord = playlist.first
        updateNowPlayingInfo()

        if playbackState == .playing {
            playbackTask?.cancel()
            startPlayback()
        }
    }

    /// 跳到最后一个
    @MainActor
    func skipToLast() {
        if !playlist.isEmpty {
            currentWordIndex = playlist.count - 1
            currentWord = playlist[currentWordIndex]
            updateNowPlayingInfo()

            if playbackState == .playing {
                playbackTask?.cancel()
                startPlayback()
            }
        }
    }

    /// 开始播放当前单词
    @MainActor
    private func startPlayback() {
        playbackTask?.cancel()

        playbackTask = Task { @MainActor in
            while currentWordIndex < playlist.count && playbackState == .playing {
                let word = playlist[currentWordIndex]
                currentWord = word
                updateNowPlayingInfo()

                // 根据播放内容播放音频
                await playCurrentWord()

                // 检查是否被取消
                if Task.isCancelled || playbackState != .playing {
                    break
                }

                // 等待间隔时间
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒

                // 检查是否自动播放下一个
                if autoPlayNext && currentWordIndex < playlist.count - 1 {
                    currentWordIndex += 1
                } else {
                    // 播放完成
                    playbackState = .paused
                    updateNowPlayingInfo()
                    break
                }
            }

            // 如果播放到最后一个，停止播放
            if currentWordIndex >= playlist.count - 1 && playbackState == .playing {
                playbackState = .paused
                updateNowPlayingInfo()
            }
        }
    }

    /// 播放当前单词的音频
    @MainActor
    private func playCurrentWord() async {
        guard let word = currentWord else { return }

        var audioPaths: [String] = []

        // 根据播放内容类型收集音频路径
        switch playbackContent {
        case .wordOnly:
            if let audioPath = word.audioPath {
                audioPaths.append(audioPath)
            }

        case .exampleOnly:
            for example in word.examples {
                if let audioPath = example.audio {
                    audioPaths.append(audioPath)
                }
            }

        case .wordAndExample:
            if let audioPath = word.audioPath {
                audioPaths.append(audioPath)
            }
            for example in word.examples {
                if let audioPath = example.audio {
                    audioPaths.append(audioPath)
                }
            }
        }

        // 依次播放所有音频
        for audioPath in audioPaths {
            if Task.isCancelled || playbackState != .playing {
                break
            }

            await playAudio(relativePath: audioPath)

            // 音频之间的间隔
            if Task.isCancelled || playbackState != .playing {
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }
    }

    /// 播放单个音频文件
    @MainActor
    private func playAudio(relativePath: String) async {
        // 检查任务是否被取消
        guard !Task.isCancelled else { return }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioURL = documentsPath.appendingPathComponent(relativePath)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return
        }

        do {
            // 停止当前播放并安全地清理continuation
            // 由于已经在MainActor上，直接访问属性，避免嵌套调度
            audioPlayer?.stop()
            if let continuation = playbackContinuation {
                playbackContinuation = nil
                continuation.resume()
            }

            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.delegate = self
            player.prepareToPlay()

            audioPlayer = player
            player.play()

            // 使用Continuation等待播放完成
            // 已经在MainActor上，直接设置continuation
            await withCheckedContinuation { continuation in
                self.playbackContinuation = continuation
            }

        } catch {
            print("❌ [PlaylistService] 音频播放失败: \(error.localizedDescription)")
        }
    }

    /// 获取进度文本
    var progressText: String {
        guard !playlist.isEmpty else { return "0/0" }
        return "\(currentWordIndex + 1)/\(playlist.count)"
    }

    /// 是否可以播放上一个
    var canPlayPrevious: Bool {
        currentWordIndex > 0
    }

    /// 是否可以播放下一个
    var canPlayNext: Bool {
        currentWordIndex < playlist.count - 1
    }
}

// MARK: - AVAudioPlayerDelegate
extension PlaylistService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // 安全地恢复continuation（避免重复resume）
            if let continuation = self.playbackContinuation {
                self.playbackContinuation = nil
                continuation.resume()
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ [PlaylistService] 音频解码错误: \(error?.localizedDescription ?? "unknown")")
        Task { @MainActor in
            // 安全地恢复continuation（避免重复resume）
            if let continuation = self.playbackContinuation {
                self.playbackContinuation = nil
                continuation.resume()
            }
        }
    }
}
