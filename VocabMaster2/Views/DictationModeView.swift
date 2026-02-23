//
//  DictationModeView.swift
//  VocabMaster2
//
//  Created on 2026/02/11.
//

import SwiftUI

struct DictationModeView: View {
    let vocabulary: Vocabulary
    let wordCount: Int

    @Binding var session: DictationSession
    @Binding var dictationTask: Task<Void, Never>?
    @Binding var isDictating: Bool
    @Binding var isPaused: Bool

    @StateObject private var audioService = AudioService.shared

    var body: some View {
        VStack(spacing: 20) {
            if !session.isCompleted {
                if !isDictating {
                    // 检查是否有未完成的听写可以恢复
                    if session.words.isEmpty || session.currentIndex == 0 {
                        // 开始听写界面
                        startScreen
                    } else {
                        // 恢复听写界面
                        resumeScreen
                    }
                } else {
                    // 听写进行中
                    dictatingScreen
                }
            } else {
                // 听写完成，显示结果检查界面
                DictationResultsView(session: session)
            }
        }
        .padding()
        .onAppear {
            // 只在首次加载或session为空时加载单词
            if session.words.isEmpty {
                loadWords()
            }
        }
    }

    private var resumeScreen: some View {
        VStack(spacing: 30) {
            Image(systemName: "pause.circle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("听写已暂停")
                    .font(.title)
                    .fontWeight(.bold)

                Text("进度: \(session.currentIndex) / \(session.totalCount)")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("点击继续按钮恢复听写", systemImage: "arrow.right.circle")
                Label("或点击重新开始从头听写", systemImage: "arrow.clockwise")
            }
            .font(.body)
            .foregroundColor(.secondary)

            VStack(spacing: 12) {
                // 继续听写按钮
                Button {
                    resumeDictation()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("继续听写")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                }

                // 重新开始按钮
                Button {
                    restartDictation()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("重新开始")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var startScreen: some View {
        VStack(spacing: 30) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            VStack(spacing: 8) {
                Text("听写模式")
                    .font(.title)
                    .fontWeight(.bold)

                Text("共 \(session.words.count) 个单词")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("播放单词音频", systemImage: "speaker.wave.2")
                Label("间隔 \(Int(session.pauseDuration)) 秒供书写", systemImage: "clock")
                Label("播放完成后输入答案", systemImage: "checkmark.circle")
            }
            .font(.body)
            .foregroundColor(.secondary)

            Button {
                startDictation()
            } label: {
                Text("开始听写")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .disabled(session.words.isEmpty)
        }
        .frame(maxHeight: .infinity)
    }

    private var dictatingScreen: some View {
        VStack(spacing: 40) {
            Text(isPaused ? "已暂停" : "听写进行中")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 16) {
                Text("\(session.currentIndex + 1) / \(session.totalCount)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.blue)

                ProgressView(value: Double(session.currentIndex + 1), total: Double(session.totalCount))
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }

            if audioService.isPlaying && !isPaused {
                HStack {
                    Image(systemName: "speaker.wave.3")
                        .font(.title3)
                    Text("播放中...")
                }
                .foregroundColor(.blue)
            }

            // 暂停/继续按钮
            Button {
                togglePause()
            } label: {
                HStack {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    Text(isPaused ? "继续" : "暂停")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isPaused ? Color.green : Color.orange)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }

    private func loadWords() {
        // 只加载待复习和已掌握的单词（未学习的不加入）
        let eligibleWords = vocabulary.words.filter { word in
            let status = word.state?.status ?? .unlearned
            return status == .reviewing || status == .mastered
        }

        // 按单词排序后取前N个
        let sortedWords = eligibleWords.sorted(by: { $0.word < $1.word })
        session.words = Array(sortedWords.prefix(wordCount))
        session.reset()
    }

    private func startDictation() {
        isDictating = true
        session.reset()
        dictationTask = Task {
            await playDictationSequence()
        }
    }

    private func resumeDictation() {
        // 继续之前的听写
        isDictating = true
        isPaused = false
        dictationTask = Task {
            await playDictationSequence()
        }
    }

    private func restartDictation() {
        // 重新开始听写
        isDictating = true
        session.reset()
        dictationTask = Task {
            await playDictationSequence()
        }
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            // 暂停音频
            audioService.stop()
        } else {
            // 继续听写
            if dictationTask == nil || dictationTask!.isCancelled {
                dictationTask = Task {
                    await playDictationSequence()
                }
            }
        }
    }

    @MainActor
    private func playDictationSequence() async {
        for (index, word) in session.words.enumerated() {
            // Check if task was cancelled
            if Task.isCancelled {
                return
            }

            // 如果需要恢复进度，从currentIndex开始
            if index < session.currentIndex {
                continue
            }

            session.currentIndex = index

            // 等待取消暂停
            while isPaused {
                if Task.isCancelled {
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            }

            // 播放单词音频
            if let audioPath = word.audioPath {
                audioService.play(relativePath: audioPath)

                // 等待音频播放完成（最多3秒）
                var waitTime = 0.0
                while audioService.isPlaying && waitTime < 3.0 {
                    // Check cancellation during wait
                    if Task.isCancelled {
                        audioService.stop()
                        return
                    }
                    // Check pause during wait
                    if isPaused {
                        audioService.stop()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    waitTime += 0.1
                }
            }

            // 间隔时间供用户书写
            var pauseTime = 0.0
            while pauseTime < session.pauseDuration {
                if Task.isCancelled {
                    return
                }
                if isPaused {
                    // 暂停期间不增加pauseTime
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    continue
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                pauseTime += 0.1
            }
        }

        // 听写完成
        session.isCompleted = true
        isDictating = false
        isPaused = false
    }
}
