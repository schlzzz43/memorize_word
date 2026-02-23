//
//  StudySessionView.swift
//  VocabMaster2
//
//  Created on 2026/01/28.
//

import SwiftUI
import SwiftData

struct StudySessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioService = AudioService.shared
    @StateObject private var settings = AppSettings.shared

    let vocabulary: Vocabulary
    let mode: StudyMode

    @State private var studyService: StudyService?
    @State private var showDetailView = false
    @State private var showEmptyAlert = false
    @State private var sessionCompleted = false
    @State private var userAnswer: String? = nil  // 保存用户的答案（用于显示错误时的对比）

    // 会话恢复相关
    @State private var showRestoreDialog = false
    @State private var savedSnapshot: StudySessionSnapshot?

    // 测试模式1：看单词，选意思
    @State private var selectedMeaning: String?
    @State private var meaningOptions: [String] = []

    // 测试模式2：看意思，选单词
    @State private var selectedWord: String?
    @State private var wordOptions: [String] = []

    // 测试模式3：听音频，默单词
    @State private var spellingInput = ""
    @State private var hasPlayedAudio = false
    @State private var hintExample: Example?
    @FocusState private var isSpellingInputFocused: Bool

    // 测试模式4：看例句，填单词
    @State private var clozeInput = ""
    @State private var processedSentence = ""
    @State private var correctAnswer = ""
    @State private var originalSentence = ""
    @State private var exampleTranslation: String?
    @FocusState private var isClozeInputFocused: Bool

    var body: some View {
        VStack {
            if let service = studyService {
                if service.isCompleted || sessionCompleted {
                    completedView
                } else if showDetailView, let task = service.currentTask {
                    WordDetailView(
                        word: task.word,
                        onNext: {
                            // 停止所有音频播放
                            audioService.stop()
                            audioService.cancelQueue()

                            showDetailView = false
                            userAnswer = nil  // 清除用户答案
                            service.moveToNext()
                            if service.isCompleted {
                                sessionCompleted = true
                            } else {
                                startNewTask()
                            }
                        },
                        showNextButton: true,
                        showCorrectResult: task.result,
                        fromDontKnow: task.fromDontKnow,
                        userAnswer: userAnswer,
                        allowDirectMastery: true,  // 允许直接标记为已掌握
                        onMastered: {
                            // 删除当前单词的剩余测试任务
                            service.skipRemainingTasksForWord(task.word)
                        }
                    )
                } else if let task = service.currentTask {
                    testView(for: task, service: service)
                }
            } else {
                ProgressView("加载中...")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击空白区域时关闭键盘
            isSpellingInputFocused = false
            isClozeInputFocused = false
        }
        .navigationTitle(mode.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(studyService != nil && !studyService!.isCompleted)
        .toolbar {
            if let service = studyService, !service.isCompleted {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("退出") {
                        // 停止所有音频播放
                        audioService.stop()
                        audioService.cancelQueue()
                        // 保存数据库更改
                        try? modelContext.save()
                        // 保存会话
                        saveSessionIfNeeded()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(service.completedWordCount)/\(service.totalWordCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            if studyService == nil {
                checkForSavedSession()
            }
        }
        .onDisappear {
            // 页面消失时停止所有音频播放
            audioService.stop()
            audioService.cancelQueue()

            // 保存数据库更改（防止数据丢失）
            try? modelContext.save()

            // 保存会话进度（如果未完成）
            saveSessionIfNeeded()
        }
        .alert("提示", isPresented: $showEmptyAlert) {
            Button("返回") {
                // 停止所有音频播放
                audioService.stop()
                audioService.cancelQueue()
                dismiss()
            }
        } message: {
            Text(emptyMessage)
        }
        .alert("发现未完成的学习", isPresented: $showRestoreDialog) {
            Button("继续学习") {
                restoreSession()
            }
            Button("重新开始") {
                // 清除保存的会话，开始新的学习
                StudySessionManager.shared.clearSession()
                initializeStudyService()
            }
            Button("取消", role: .cancel) {
                dismiss()
            }
        } message: {
            if let snapshot = savedSnapshot {
                let progress = snapshot.currentTaskIndex + 1
                let total = snapshot.tasks.count
                Text("你有一个未完成的\(snapshot.mode.toStudyMode().displayName)会话\n进度：\(progress)/\(total)")
            } else {
                Text("是否继续上次的学习？")
            }
        }
    }

    private var emptyMessage: String {
        switch mode {
        case .newLearning:
            return "暂无未学习的单词"
        case .review:
            return "暂无待复习的单词"
        case .randomTest:
            return "暂无可测试的单词"
        }
    }

    @ViewBuilder
    private func testView(for task: TestTask, service: StudyService) -> some View {
        VStack(spacing: 20) {
            // 进度条
            ProgressView(value: service.progress)
                .padding(.horizontal)

            Spacer()

            // 根据测试模式显示不同的UI
            switch task.mode {
            case .wordToMeaning:
                wordToMeaningView(task: task, service: service)
            case .meaningToWord:
                meaningToWordView(task: task, service: service)
            case .audioToSpelling:
                audioToSpellingView(task: task, service: service)
            case .exampleToWord:
                exampleToWordView(task: task, service: service)
            }

            Spacer()

            // 底部按钮区域 - 对于选择题模式，只显示"我不认识"按钮
            if task.mode == .wordToMeaning || task.mode == .meaningToWord {
                Button {
                    handleDontKnow(service: service)
                } label: {
                    Text("我不认识")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange, lineWidth: 2)
                        )
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    // MARK: - 测试模式1：看单词，选意思

    @ViewBuilder
    private func wordToMeaningView(task: TestTask, service: StudyService) -> some View {
        VStack(spacing: 30) {
            Text(task.word.word)
                .font(.system(size: 48, weight: .bold))
                .padding()

            Text("选择正确的意思")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                ForEach(meaningOptions, id: \.self) { option in
                    Button {
                        selectedMeaning = option
                        submitWordToMeaning(task: task, service: service)
                    } label: {
                        Text(option)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func submitWordToMeaning(task: TestTask, service: StudyService) {
        let correct = selectedMeaning == task.word.meaning

        // 保存用户答案（仅当回答错误时）
        if !correct, let selected = selectedMeaning {
            userAnswer = selected
        }

        service.processTestResult(passed: correct)

        if correct {
            audioService.playCorrectSound()
        } else {
            audioService.playWrongSound()
        }

        // 直接跳转到详细页
        showDetailView = true
    }

    // MARK: - 测试模式2：看意思，选单词

    @ViewBuilder
    private func meaningToWordView(task: TestTask, service: StudyService) -> some View {
        VStack(spacing: 30) {
            Text(task.word.meaning)
                .font(.system(size: 32, weight: .medium))
                .padding()
                .multilineTextAlignment(.center)

            Text("选择正确的单词")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                ForEach(wordOptions, id: \.self) { option in
                    Button {
                        selectedWord = option
                        submitMeaningToWord(task: task, service: service)
                    } label: {
                        Text(option)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func submitMeaningToWord(task: TestTask, service: StudyService) {
        let correct = selectedWord == task.word.word

        // 保存用户答案（仅当回答错误时）
        if !correct, let selected = selectedWord {
            userAnswer = selected
        }

        service.processTestResult(passed: correct)

        if correct {
            audioService.playCorrectSound()
        } else {
            audioService.playWrongSound()
        }

        // 直接跳转到详细页
        showDetailView = true
    }

    // MARK: - 测试模式3：听音频，默单词

    @ViewBuilder
    private func audioToSpellingView(task: TestTask, service: StudyService) -> some View {
        VStack(spacing: 30) {
            // 播放按钮
            Button {
                playWordAudio(task: task)
            } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
            }

            Text("听音频，默写单词")
                .font(.title3)
                .foregroundColor(.secondary)

            // Hint按钮
            if let example = hintExample {
                Button {
                    audioService.play(relativePath: example.audio)
                } label: {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                        Text("提示：播放例句")
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                }
            }

            // 输入框
            TextField("请输入单词", text: $spellingInput)
                .font(.system(size: 28, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSpellingInputFocused)
                .underlineTextField(isFocused: isSpellingInputFocused)
                .padding(.horizontal)

            // 底部双按钮布局
            HStack(spacing: 12) {
                // 左侧：我不认识（次要按钮）
                Button {
                    handleDontKnow(service: service)
                } label: {
                    Text("我不认识")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange, lineWidth: 2)
                        )
                }

                // 右侧：提交（主要按钮）
                Button {
                    submitAudioToSpelling(task: task, service: service)
                } label: {
                    Text("提交")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(spellingInput.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(spellingInput.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            if !hasPlayedAudio {
                playWordAudio(task: task)
                hasPlayedAudio = true
            }
        }
    }

    private func playWordAudio(task: TestTask) {
        audioService.play(relativePath: task.word.audioPath)
        // 随机选择一个例句作为hint
        if !task.word.examples.isEmpty {
            hintExample = task.word.examples.randomElement()
        }
    }

    private func submitAudioToSpelling(task: TestTask, service: StudyService) {
        // 关闭键盘
        isSpellingInputFocused = false

        let correct = service.checkSpelling(input: spellingInput, word: task.word)

        // 保存用户答案（仅当回答错误时）
        if !correct {
            userAnswer = spellingInput
        }

        service.processTestResult(passed: correct)

        if correct {
            audioService.playCorrectSound()
        } else {
            audioService.playWrongSound()
        }

        // 直接跳转到详细页
        showDetailView = true
    }

    // MARK: - 测试模式4：看例句，填单词

    @ViewBuilder
    private func exampleToWordView(task: TestTask, service: StudyService) -> some View {
        VStack(spacing: 30) {
            // 显示例句的翻译/意思
            if let translation = exampleTranslation {
                Text(translation)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // 显示处理后的例句（带空格）
            Text(processedSentence)
                .font(.title3)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .multilineTextAlignment(.center)

            // 输入框
            TextField("请输入单词的正确形式", text: $clozeInput)
                .font(.system(size: 28, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isClozeInputFocused)
                .underlineTextField(isFocused: isClozeInputFocused)
                .padding(.horizontal)

            Text("提示：需要填写单词在句子中的实际形式")
                .font(.caption)
                .foregroundColor(.secondary)

            // 底部双按钮布局
            HStack(spacing: 12) {
                // 左侧：我不认识（次要按钮）
                Button {
                    handleDontKnow(service: service)
                } label: {
                    Text("我不认识")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange, lineWidth: 2)
                        )
                }

                // 右侧：提交（主要按钮）
                Button {
                    submitExampleToWord(task: task, service: service)
                } label: {
                    Text("提交")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(clozeInput.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(clozeInput.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func submitExampleToWord(task: TestTask, service: StudyService) {
        // 关闭键盘
        isClozeInputFocused = false

        let correct = service.checkClozeAnswer(userInput: clozeInput, correctAnswer: correctAnswer)

        // 保存用户答案（仅当回答错误时）
        if !correct {
            userAnswer = clozeInput
        }

        service.processTestResult(passed: correct)

        if correct {
            audioService.playCorrectSound()
        } else {
            audioService.playWrongSound()
        }

        // 直接跳转到详细页
        showDetailView = true
    }

    // MARK: - "我不认识"处理

    private func handleDontKnow(service: StudyService) {
        // 关闭键盘
        isSpellingInputFocused = false
        isClozeInputFocused = false

        service.processDontKnow()
        showDetailView = true
    }

    // MARK: - 完成视图

    private var completedView: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("完成！")
                .font(.largeTitle)
                .fontWeight(.bold)

            if let service = studyService {
                Text("完成了 \(service.testTasks.count) 个测试")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Button {
                // 停止所有音频播放
                audioService.stop()
                audioService.cancelQueue()
                // 清除保存的会话
                StudySessionManager.shared.clearSession()
                dismiss()
            } label: {
                Text("返回")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 初始化

    private func initializeStudyService() {
        let service = StudyService(modelContext: modelContext)

        switch mode {
        case .newLearning:
            service.startNewLearning(vocabulary: vocabulary)
        case .review:
            service.startReview(vocabulary: vocabulary)
        case .randomTest:
            service.startRandomTest(vocabulary: vocabulary)
        }

        if service.testTasks.isEmpty {
            showEmptyAlert = true
        } else {
            studyService = service
            startNewTask()
        }
    }

    private func startNewTask() {
        guard let service = studyService, let task = service.currentTask else { return }

        // 重置所有状态
        selectedMeaning = nil
        selectedWord = nil
        spellingInput = ""
        hasPlayedAudio = false
        hintExample = nil
        clozeInput = ""
        exampleTranslation = nil
        userAnswer = nil  // 清除用户答案

        // 关闭键盘
        isSpellingInputFocused = false
        isClozeInputFocused = false

        // 根据测试模式准备数据
        switch task.mode {
        case .wordToMeaning:
            meaningOptions = service.generateMeaningOptions(for: task.word, from: vocabulary)

        case .meaningToWord:
            wordOptions = service.generateWordOptions(for: task.word, from: vocabulary)

        case .audioToSpelling:
            // 会在 onAppear 中播放音频
            break

        case .exampleToWord:
            if let result = service.prepareClozeTest(for: task.word) {
                processedSentence = result.processedSentence
                correctAnswer = result.correctAnswer
                originalSentence = result.originalSentence
                exampleTranslation = result.translation
            } else {
                // 如果没有例句，自动标记为失败并跳过
                service.processTestResult(passed: false)
                service.moveToNext()
                if !service.isCompleted {
                    startNewTask()
                } else {
                    sessionCompleted = true
                }
            }
        }
    }

    // MARK: - 会话保存和恢复

    /// 检查是否有保存的会话
    private func checkForSavedSession() {
        guard let snapshot = StudySessionManager.shared.getSavedSession() else {
            // 没有保存的会话，正常初始化
            initializeStudyService()
            return
        }

        // 检查保存的会话是否属于当前词汇表
        guard snapshot.vocabularyId == "\(vocabulary.id)" else {
            StudySessionManager.shared.clearSession()
            initializeStudyService()
            return
        }

        // 检查词汇表是否发生变更
        if StudySessionManager.shared.isVocabularyChanged(savedHash: snapshot.vocabularyHash, vocabulary: vocabulary) {
            StudySessionManager.shared.clearSession()
            initializeStudyService()
            return
        }

        // 检查会话模式是否匹配
        guard snapshot.mode.toStudyMode() == mode else {
            StudySessionManager.shared.clearSession()
            initializeStudyService()
            return
        }

        // 显示恢复对话框
        savedSnapshot = snapshot
        showRestoreDialog = true
    }

    /// 恢复保存的会话
    private func restoreSession() {
        guard let snapshot = savedSnapshot else {
            initializeStudyService()
            return
        }

        let service = StudyService(modelContext: modelContext)

        if service.restoreFromSnapshot(snapshot, vocabulary: vocabulary) {
            studyService = service
            startNewTask()
        } else {
            StudySessionManager.shared.clearSession()
            initializeStudyService()
        }

        savedSnapshot = nil
    }

    /// 保存会话（如果需要）
    private func saveSessionIfNeeded() {
        guard let service = studyService,
              !service.isCompleted,
              !sessionCompleted else {
            // 会话已完成，清除保存的数据
            StudySessionManager.shared.clearSession()
            return
        }

        // 保存当前进度
        let snapshot = service.createSnapshot(vocabulary: vocabulary)
        StudySessionManager.shared.saveSession(snapshot)
    }
}
