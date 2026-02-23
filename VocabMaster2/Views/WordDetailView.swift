//
//  WordDetailView.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import SwiftUI
import SwiftData

struct WordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var audioService = AudioService.shared
    @StateObject private var settings = AppSettings.shared

    let word: Word
    var onNext: (() -> Void)?
    var showNextButton: Bool = false
    var showCorrectResult: Bool? = nil  // nil=不显示, true=正确, false=错误
    var fromDontKnow: Bool = false
    var userAnswer: String? = nil  // 用户的答案（用于显示错误对比）
    var allowDirectMastery: Bool = false  // 是否允许直接标记为已掌握
    var onMastered: (() -> Void)? = nil  // 点击掌握按钮的回调
    var isEditable: Bool = false  // 是否允许编辑
    var disableAutoPlay: Bool = false  // 禁用自动播放（用于播放器tab中）

    @State private var showWebLookup = false  // 控制Safari视图显示
    @State private var isEditing = false  // 编辑模式
    @State private var editedPronunciation: String = ""
    @State private var editedMeaning: String = ""
    @State private var editedExamples: [Example] = []
    @State private var showValidationAlert = false  // 显示验证警告

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 单词
                Text(word.word)
                    .font(.system(size: 36, weight: .bold))
                    .padding(.top, 20)

                // 发音和播放按钮
                HStack(spacing: 12) {
                    if settings.showPronunciation {
                        if isEditing {
                            TextField("发音", text: $editedPronunciation)
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text(word.pronunciation)
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        audioService.play(relativePath: word.audioPath)
                    } label: {
                        Image(systemName: audioService.playbackFailed ? "speaker.slash" : (audioService.isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2.fill"))
                            .font(.title2)
                            .foregroundColor(audioService.playbackFailed ? .gray : .blue)
                    }

                    Button {
                        showWebLookup = true
                    } label: {
                        Image(systemName: "safari")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }

                // 词义
                if isEditing {
                    TextField("词义", text: $editedMeaning, axis: .vertical)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                        .padding(.horizontal)
                } else {
                    Text(word.meaning)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // 例句
                if isEditing {
                    // 编辑模式下的例句
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("例句")
                                .font(.headline)
                            Spacer()
                            if editedExamples.count < 5 {  // 最多5个例句
                                Button {
                                    addExample()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(.horizontal)

                        ForEach(Array(editedExamples.enumerated()), id: \.offset) { index, example in
                            EditableExampleCard(
                                example: $editedExamples[index],
                                index: index + 1,
                                onDelete: {
                                    deleteExample(at: index)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // 查看模式下的例句
                    let displayExamples = Array(word.examples.prefix(settings.exampleDisplayCount))
                    if !displayExamples.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("💡 长按例句中的单词可查询释义")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(displayExamples.enumerated()), id: \.offset) { index, example in
                                    ExampleCard(example: example, index: index + 1)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // 状态信息或测试结果
                if !fromDontKnow {
                    if let isCorrect = showCorrectResult {
                        // 显示测试结果
                        VStack(spacing: 8) {
                            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(isCorrect ? .green : .red)

                            Text(isCorrect ? "回答正确" : "回答错误")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(isCorrect ? .green : .red)

                            // 显示答案对比（仅当回答错误且有用户答案时）
                            if !isCorrect, let answer = userAnswer {
                                Divider()
                                    .padding(.vertical, 4)

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Text("你的答案:")
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                        Text(answer)
                                            .foregroundColor(.red)
                                            .fontWeight(.medium)
                                            .font(.body)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else {
                        // 显示当前状态
                        VStack(spacing: 8) {
                            HStack {
                                Text("当前状态:")
                                    .foregroundColor(.secondary)
                                StatusBadge(status: word.state?.status ?? .unlearned)
                            }

                            HStack {
                                Text("已掌握进度:")
                                    .foregroundColor(.secondary)
                                Text("\(word.state?.masteryCount ?? 0)/\(settings.masteryThreshold)")
                                    .fontWeight(.medium)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }

                // 下一个按钮
                if showNextButton {
                    Button {
                        // 停止当前播放的音频
                        audioService.stop()
                        // 取消队列任务
                        audioService.cancelQueue()
                        // 进入下一个流程
                        onNext?()
                    } label: {
                        Text("下一个")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }

                // 掌握按钮（仅在回答正确时显示，回答错误或"我不认识"时不显示）
                if allowDirectMastery,
                   word.state?.status != .mastered,
                   showNextButton,
                   showCorrectResult == true {
                    Button {
                        markAsMastered()
                    } label: {
                        HStack {
                            Image(systemName: "hand.thumbsup.fill")
                            Text("掌握")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(LinearGradient(colors: [Color.green, Color.green.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                }

                Spacer(minLength: 50)
            }
        }
        .navigationTitle(word.word)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditable {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        HStack(spacing: 12) {
                            Button("取消") {
                                cancelEditing()
                            }
                            Button("保存") {
                                saveChanges()
                            }
                            .fontWeight(.semibold)
                        }
                    } else {
                        Button("编辑") {
                            startEditing()
                        }
                    }
                }
            }
        }
        .onAppear {
            // 如果禁用自动播放，直接返回（用于播放器tab）
            if disableAutoPlay {
                return
            }

            if settings.autoPlayAudio {
                // 如果显示了测试结果（正确或错误），说明刚播放了音效
                // 需要延迟一下再播放单词音频，让音效有时间播放完成
                let delay: TimeInterval = (showCorrectResult != nil) ? 0.6 : 0

                // 先停止之前的播放
                audioService.stop()
                audioService.cancelQueue()

                // 延迟后播放
                if delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.playAudioQueue()
                    }
                } else {
                    playAudioQueue()
                }
            }
        }
        .onDisappear {
            // 页面消失时停止所有音频播放
            audioService.stop()
            audioService.cancelQueue()
        }
        .sheet(isPresented: $showWebLookup) {
            if let url = createSearchURL() {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .alert("验证失败", isPresented: $showValidationAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("发音和词义不能为空")
        }
    }

    /// 播放音频队列
    private func playAudioQueue() {
        // 构建音频队列：先播放单词音频，然后按顺序播放例句音频
        var audioPaths: [String?] = [word.audioPath]
        let displayExamples = Array(word.examples.prefix(settings.exampleDisplayCount))
        for example in displayExamples {
            audioPaths.append(example.audio)
        }
        // 播放队列，间隔1秒
        audioService.playQueue(paths: audioPaths, interval: 1.0)
    }

    /// 创建搜索URL
    private func createSearchURL() -> URL? {
        let query = "\(word.word) 中文释义"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }

    /// 直接标记单词为已掌握
    private func markAsMastered() {
        // 如果单词没有状态，创建一个新的
        if word.state == nil {
            let newState = WordState(status: .mastered)
            newState.word = word
            modelContext.insert(newState)
        }

        // 标记为已掌握
        word.state?.markAsMastered(masteryThreshold: settings.masteryThreshold)

        // 保存到数据库
        try? modelContext.save()

        // 触觉反馈
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // 调用掌握回调（删除剩余测试任务）
        onMastered?()

        // 如果在学习流程中，0.5秒后自动进入下一个
        if let next = onNext {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                next()
            }
        }
    }

    /// 开始编辑
    private func startEditing() {
        editedPronunciation = word.pronunciation
        editedMeaning = word.meaning
        editedExamples = word.examples
        isEditing = true
    }

    /// 保存更改
    private func saveChanges() {
        // 验证必填字段
        guard !editedPronunciation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !editedMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showValidationAlert = true
            return
        }

        // 保存更改
        word.pronunciation = editedPronunciation
        word.meaning = editedMeaning
        word.examples = editedExamples

        // 持久化到数据库
        try? modelContext.save()

        isEditing = false
    }

    /// 取消编辑
    private func cancelEditing() {
        isEditing = false
        // 恢复原始值（通过重新读取word的属性）
        editedPronunciation = word.pronunciation
        editedMeaning = word.meaning
        editedExamples = word.examples
    }

    /// 添加例句
    private func addExample() {
        let newExample = Example(text: "", translation: nil, audio: nil)
        editedExamples.append(newExample)
    }

    /// 删除例句
    private func deleteExample(at index: Int) {
        editedExamples.remove(at: index)
    }
}

// MARK: - 例句卡片
struct ExampleCard: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var audioService = AudioService.shared
    @StateObject private var settings = AppSettings.shared

    let example: Example
    let index: Int

    // 查词功能状态
    @State private var selectedWord: String?
    @State private var showLookup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("例句\(index):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // 将音频按钮移到标题行
                if example.audio != nil {
                    Button {
                        audioService.play(relativePath: example.audio)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
            }

            // 例句文本 - 给予完整宽度，避免被截断
            SelectableTextView(
                text: example.text,
                font: .preferredFont(forTextStyle: .body),
                textColor: .label,
                backgroundColor: .clear
            ) { word in
                selectedWord = word
                showLookup = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 显示翻译
            if let translation = example.translation, !translation.isEmpty {
                Text(translation)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
        .sheet(isPresented: $showLookup) {
            if let word = selectedWord {
                WordLookupPopover(word: word) {
                    showLookup = false
                }
            }
        }
    }
}

// MARK: - 可编辑例句卡片
struct EditableExampleCard: View {
    @Binding var example: Example
    let index: Int
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("例句\(index):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            // 例句文本
            VStack(alignment: .leading, spacing: 4) {
                Text("例句:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("输入例句", text: $example.text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            // 翻译
            VStack(alignment: .leading, spacing: 4) {
                Text("翻译:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("输入翻译（可选）", text: Binding(
                    get: { example.translation ?? "" },
                    set: { example.translation = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            // 音频路径（只读显示）
            if let audioPath = example.audio {
                HStack {
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text(audioPath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - 状态徽章
struct StatusBadge: View {
    let status: WordStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
            Text(status.displayName)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.2))
        .foregroundColor(statusColor)
        .cornerRadius(8)
    }

    private var statusColor: Color {
        switch status {
        case .unlearned:
            return .gray
        case .reviewing:
            return .orange
        case .mastered:
            return .green
        }
    }
}

#Preview {
    NavigationStack {
        WordDetailView(
            word: {
                let word = Word(word: "apple", pronunciation: "/ˈæpl/", meaning: "n. 苹果")
                word.examples = [
                    Example(text: "I eat an apple.", translation: "我吃一个苹果。", audio: nil),
                    Example(text: "The apple is red.", translation: "这个苹果是红色的。", audio: nil)
                ]
                return word
            }(),
            showNextButton: true
        )
    }
}
