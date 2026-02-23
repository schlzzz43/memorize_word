//
//  PlayerTabView.swift
//  VocabMaster2
//
//  Created on 2026/02/11.
//

import SwiftUI
import SwiftData

struct PlayerTabView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AppSettings.shared
    @StateObject private var playlistService = PlaylistService.shared

    @Query private var vocabularies: [Vocabulary]

    @State private var isDictationMode = false  // 播放模式 vs 听写模式
    @State private var currentVocabulary: Vocabulary?
    @StateObject private var audioService = AudioService.shared
    @State private var dictationWordCount: Int = 20  // 听写单词个数

    // 听写状态（提升到这一层以保持任务持续）
    @State private var dictationSession = DictationSession()
    @State private var dictationTask: Task<Void, Never>?
    @State private var isDictating = false
    @State private var isPausedDictation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 模式切换器
                Picker("模式", selection: $isDictationMode) {
                    Text("播放模式").tag(false)
                    Text("听写模式").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)
                .onChange(of: isDictationMode) { _, newValue in
                    // 切换模式时处理音频
                    if newValue == false {
                        // 切换到播放模式，暂停听写（保留进度）
                        if isDictating && !isPausedDictation {
                            pauseDictation()
                        }
                    } else {
                        // 切换到听写模式，停止播放
                        playlistService.stop()
                    }
                }

                // 设置区域
                VStack(spacing: 12) {
                    if isDictationMode {
                        // 听写模式设置
                        HStack {
                            Text("听写单词数:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Stepper("\(dictationWordCount) 个", value: $dictationWordCount, in: 5...100, step: 5)
                                .font(.subheadline)
                        }
                        .padding(.horizontal)
                    } else {
                        // 播放模式设置
                        HStack(spacing: 20) {
                            // 播放顺序
                            Menu {
                                Picker("播放顺序", selection: $playlistService.playbackOrder) {
                                    ForEach(PlaybackOrder.allCases, id: \.self) { order in
                                        Text(order.rawValue).tag(order)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text(playlistService.playbackOrder.rawValue)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(8)
                            }
                            .onChange(of: playlistService.playbackOrder) { _, _ in
                                playlistService.reapplyPlaybackOrder()
                            }

                            // 播放内容
                            Menu {
                                Picker("播放内容", selection: $playlistService.playbackContent) {
                                    ForEach(PlaybackContent.allCases, id: \.self) { content in
                                        Text(content.rawValue).tag(content)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "speaker.wave.2")
                                    Text(playlistService.playbackContent.rawValue)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)

                Divider()

                // 内容区域
                if let vocab = currentVocabulary {
                    if isDictationMode {
                        // 听写模式
                        DictationModeView(
                            vocabulary: vocab,
                            wordCount: dictationWordCount,
                            session: $dictationSession,
                            dictationTask: $dictationTask,
                            isDictating: $isDictating,
                            isPaused: $isPausedDictation
                        )
                    } else {
                        // 播放模式
                        playModeContent(vocabulary: vocab)
                    }
                } else {
                    // 无词库选中
                    ContentUnavailableView(
                        "未选择词库",
                        systemImage: "books.vertical",
                        description: Text("请先在设置中选择当前词库")
                    )
                }
            }
            .navigationTitle("播放器")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadCurrentVocabulary()
            }
            .onChange(of: settings.currentVocabularyId) { _, _ in
                loadCurrentVocabulary()
            }
            .onAppear {
                // Tab出现时不做任何处理，保持当前状态
            }
            .onDisappear {
                // 离开播放器tab时，暂停所有音频播放
                if isDictationMode {
                    // 听写模式：暂停听写（保留进度）
                    if isDictating && !isPausedDictation {
                        pauseDictation()
                    }
                } else {
                    // 播放模式：暂停播放（保留进度和位置）
                    if playlistService.playbackState == .playing {
                        playlistService.pause()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func playModeContent(vocabulary: Vocabulary) -> some View {
        ZStack(alignment: .bottom) {
            // 当前播放单词详情
            if let currentWord = playlistService.currentWord {
                ScrollView {
                    WordDetailView(word: currentWord, isEditable: false, disableAutoPlay: true)
                        .padding(.bottom, 120)  // 为 mini player 和 tab bar 留出空间
                }
            } else {
                ContentUnavailableView(
                    "点击播放按钮开始",
                    systemImage: "play.circle",
                    description: Text("将播放当前词库的所有单词")
                )
            }

            // Mini Player 控制条
            HStack(spacing: 16) {
                // 上一个
                Button {
                    playlistService.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(playlistService.currentWordIndex <= 0)

                Spacer()

                // 播放/暂停
                Button {
                    if playlistService.playbackState == .playing {
                        playlistService.pause()
                    } else {
                        if playlistService.playlist.isEmpty {
                            startPlayback(vocabulary: vocabulary)
                        } else {
                            playlistService.play()
                        }
                    }
                } label: {
                    Image(systemName: playlistService.playbackState == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }

                Spacer()

                // 下一个
                Button {
                    playlistService.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(playlistService.currentWordIndex >= playlistService.playlist.count - 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .padding(.bottom, 8)  // 额外的底部间距，避免与 tab bar 重叠
        }
    }

    private func loadCurrentVocabulary() {
        // 使用isSelected属性找到当前选中的词库
        currentVocabulary = vocabularies.first { $0.isSelected }
    }

    private func startPlayback(vocabulary: Vocabulary) {
        let words = vocabulary.words.sorted(by: { $0.word < $1.word })
        playlistService.loadPlaylist(words)
        playlistService.play()
    }

    private func stopAllAudio() {
        // 停止播放模式的音频
        playlistService.stop()
        // 停止听写模式的音频
        audioService.stop()
        audioService.cancelQueue()
    }

    /// 暂停听写（保留状态和进度）
    func pauseDictation() {
        guard isDictating else { return }
        isPausedDictation = true
        audioService.stop()
    }

    /// 完全停止听写（清空所有状态）
    private func stopDictationCompletely() {
        dictationTask?.cancel()
        dictationTask = nil
        audioService.stop()
        audioService.cancelQueue()
        isDictating = false
        isPausedDictation = false
        // 重置session
        dictationSession = DictationSession()
    }
}
