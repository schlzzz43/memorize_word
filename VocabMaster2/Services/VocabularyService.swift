//
//  VocabularyService.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import SwiftData

/// 词库导入结果
///
/// 封装ZIP导入操作的结果统计，提供友好的摘要信息供UI显示。
/// 记录成功、失败、重复的单词数量，以及详细的错误信息列表。
struct ImportResult {
    /// 成功导入的单词数量
    var successCount: Int = 0

    /// 导入失败的单词数量（格式错误、解析失败等）
    var failedCount: Int = 0

    /// 跳过的重复单词数量（词库中已存在）
    var duplicateCount: Int = 0

    /// 详细错误信息列表（用于调试和显示给用户）
    var errorMessages: [String] = []

    /// 生成导入结果的摘要文本
    ///
    /// - Returns: 格式化的摘要字符串，例如："成功导入20个单词，跳过5个重复单词"
    ///
    /// **格式规则：**
    /// - 只显示非零的统计项
    /// - 使用中文逗号分隔
    /// - 优先级：成功 > 重复 > 失败
    var summary: String {
        var parts: [String] = []
        if successCount > 0 {
            parts.append("成功导入\(successCount)个单词")
        }
        if duplicateCount > 0 {
            parts.append("跳过\(duplicateCount)个重复单词")
        }
        if failedCount > 0 {
            parts.append("失败\(failedCount)个")
        }
        return parts.joined(separator: "，")
    }
}

/// 词库服务类
///
/// 负责词库和单词的完整生命周期管理，是词库管理的核心业务逻辑层。主要功能包括：
/// - 词库的CRUD操作（创建、读取、更新、删除）
/// - 从ZIP文件导入词库（包括文本解析和音频文件处理）
/// - 当前词库的选择和切换
/// - 单词的删除和音频文件清理
/// - 学习数据的重置（保留词库但清除学习进度）
///
/// **架构设计：**
/// - 作为MVVM模式中的Service层
/// - @MainActor保证所有操作在主线程执行，确保UI更新线程安全
/// - 所有文件操作（音频复制、删除）都在此处集中管理
///
/// **数据流向：**
/// ```
/// ZIP文件 → 解压 → 解析txt → 创建Word/WordState → 复制音频 → SwiftData持久化
/// ```
///
/// **重要业务规则：**
/// - 同名词库不允许重复导入
/// - 删除词库会级联删除所有关联数据（Word, WordState, StudyRecord）和音频文件
/// - 重置学习数据只清除进度，保留词库和单词
/// - 如果是第一个导入的词库，自动设为当前词库
/// - 导入后自动关联已有的习题集
///
/// **使用示例：**
/// ```swift
/// let service = VocabularyService(modelContext: context)
/// let (vocab, result) = await service.importFromZip(zipURL: url)
/// if let vocabulary = vocab {
///     print("导入成功: \(result.summary)")
/// }
/// ```
@MainActor
class VocabularyService {

    // MARK: - 依赖项

    /// SwiftData上下文，用于数据库操作
    private var modelContext: ModelContext

    // MARK: - 初始化

    /// 初始化词库服务
    ///
    /// - Parameter modelContext: SwiftData上下文，用于数据库读写操作
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 私有辅助方法

    /// 将单词/词组转换为音频文件名格式（空格替换为下划线）
    ///
    /// - Parameter word: 原始单词文本（可能包含空格）
    /// - Returns: 转换后的文件名（空格替换为下划线）
    ///
    /// **为什么需要这个转换？**
    /// - 文件系统中空格可能引起路径解析问题
    /// - 统一音频文件命名规范（"according to" → "according_to.mp3"）
    /// - 与ZIP包内的音频文件命名保持一致
    ///
    /// **示例：**
    /// - "apple" → "apple"
    /// - "according to" → "according_to"
    /// - "give up" → "give_up"
    private func audioFileName(for word: String) -> String {
        return word.replacingOccurrences(of: " ", with: "_")
    }

    // MARK: - 词库查询

    /// 获取所有词库列表
    ///
    /// - Returns: 所有词库数组，按创建时间倒序排列（最新的在前）
    ///
    /// **排序规则：**
    /// - 按createdAt降序排序，新导入的词库排在最前面
    /// - 如果查询失败返回空数组（不抛出错误）
    func getAllVocabularies() -> [Vocabulary] {
        let descriptor = FetchDescriptor<Vocabulary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// 获取当前选中的词库
    ///
    /// - Returns: 当前选中的词库对象，如果没有选中任何词库返回nil
    ///
    /// **业务规则：**
    /// - 同时只能有一个词库处于选中状态（isSelected = true）
    /// - 用于学习、复习、随机测试的单词来源
    /// - 如果查询失败返回nil
    func getCurrentVocabulary() -> Vocabulary? {
        let descriptor = FetchDescriptor<Vocabulary>(predicate: #Predicate { $0.isSelected == true })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - 词库管理

    /// 设置当前词库（切换学习词库）
    ///
    /// - Parameter vocabulary: 要设为当前的词库对象
    ///
    /// **执行流程：**
    /// 1. 遍历所有词库，将它们的isSelected设为false（取消所有选中状态）
    /// 2. 将目标词库的isSelected设为true（设为当前词库）
    /// 3. 保存数据库变更
    ///
    /// **业务规则：**
    /// - 同时只能有一个词库被选中
    /// - 切换词库会影响学习、复习、随机测试的单词来源
    /// - UI中的"当前词库"显示会自动更新
    func setCurrentVocabulary(_ vocabulary: Vocabulary) {
        // 先取消所有词库的选中状态，确保只有一个词库被选中
        let allVocabularies = getAllVocabularies()
        for vocab in allVocabularies {
            if vocab.isSelected {
                vocab.isSelected = false
            }
        }

        // 设置当前词库为选中状态
        vocabulary.isSelected = true

        // 持久化变更
        try? modelContext.save()
    }

    /// 创建新词库（空词库，用于手动添加单词）
    ///
    /// - Parameter name: 词库名称
    /// - Returns: 创建的词库对象
    ///
    /// **使用场景：**
    /// - 用户手动创建词库（目前未在UI中使用）
    /// - 单元测试
    ///
    /// **注意：**
    /// - 不检查重名（调用方需要自行检查）
    /// - 创建后不自动设为当前词库
    /// - 创建的是空词库，需要后续导入单词
    func createVocabulary(name: String) -> Vocabulary {
        let vocabulary = Vocabulary(name: name)
        modelContext.insert(vocabulary)
        try? modelContext.save()
        return vocabulary
    }

    /// 删除词库（级联删除所有相关数据和音频文件）
    ///
    /// - Parameter vocabulary: 要删除的词库对象
    ///
    /// **删除内容：**
    /// 1. 音频文件夹：`Documents/Audio/[词库名]/`及其所有内容
    /// 2. 数据库记录：SwiftData级联删除所有关联数据
    ///    - 词库的所有单词（Word）
    ///    - 所有单词的状态（WordState）
    ///    - 所有学习记录（StudyRecord）
    ///
    /// **为什么要手动删除音频文件？**
    /// - SwiftData只负责数据库记录的级联删除
    /// - 音频文件存储在文件系统中，需要手动清理
    /// - 如果不删除音频文件，会造成磁盘空间浪费
    ///
    /// **注意：**
    /// - 操作不可逆，调用前应该有确认对话框
    /// - 如果音频文件删除失败（文件不存在等），不影响数据库删除
    /// - 如果删除的是当前词库，调用方需要自行处理UI状态
    func deleteVocabulary(_ vocabulary: Vocabulary) {
        // 删除音频文件夹（包括所有单词音频和例句音频）
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioFolderPath = documentsPath.appendingPathComponent("Audio/\(vocabulary.name)")

        // 删除整个音频文件夹（如果失败不抛出错误，继续删除数据库）
        try? FileManager.default.removeItem(at: audioFolderPath)

        // 删除数据库记录（SwiftData会自动级联删除所有关联的Word, WordState, StudyRecord）
        modelContext.delete(vocabulary)
        try? modelContext.save()
    }

    /// 删除单词（级联删除相关音频文件）
    ///
    /// - Parameter word: 要删除的单词对象
    ///
    /// **删除内容：**
    /// 1. 单词音频文件：`Documents/Audio/[词库名]/[单词].mp3`
    /// 2. 例句音频文件：`Documents/Audio/[词库名]/[单词]_1.mp3`, `[单词]_2.mp3`, ...
    /// 3. 数据库记录：SwiftData级联删除
    ///    - 单词状态（WordState）
    ///    - 所有学习记录（StudyRecord）
    ///
    /// **为什么要手动删除音频文件？**
    /// - Word模型中的audioPath只是字符串路径，不是文件引用
    /// - SwiftData不会自动删除文件系统中的文件
    /// - 必须手动遍历所有音频路径并逐个删除
    ///
    /// **注意：**
    /// - 如果单词没有关联词库（word.vocabulary == nil），直接返回
    /// - 音频文件可能不存在（导入时没有提供），删除失败不影响流程
    func deleteWord(_ word: Word) {
        // 安全检查：单词必须属于某个词库
        guard word.vocabulary != nil else { return }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        // 删除单词音频文件（如果存在）
        if let audioPath = word.audioPath {
            let audioURL = documentsPath.appendingPathComponent(audioPath)
            try? FileManager.default.removeItem(at: audioURL)
        }

        // 删除所有例句音频文件
        for example in word.examples {
            if let exampleAudio = example.audio {
                let audioURL = documentsPath.appendingPathComponent(exampleAudio)
                try? FileManager.default.removeItem(at: audioURL)
            }
        }

        // 删除数据库记录（SwiftData会自动级联删除WordState和StudyRecord）
        modelContext.delete(word)
        try? modelContext.save()
    }

    // MARK: - 词库导入

    /// 从ZIP文件导入词库（包括单词数据和音频文件）
    ///
    /// - Parameters:
    ///   - zipURL: ZIP文件的URL路径（可以是本地文件或临时文件）
    ///   - vocabularyName: 词库名称（可选，如果为nil则从txt文件名提取）
    /// - Returns: 元组 (导入的词库对象, 导入结果统计)，如果导入失败词库对象为nil
    ///
    /// **ZIP文件结构要求：**
    /// ```
    /// vocabulary.zip
    /// ├── vocabulary.txt              # 必需：单词数据文件
    /// ├── word1.mp3                   # 可选：单词音频
    /// ├── word1_1.mp3                 # 可选：例句1音频
    /// ├── word1_2.mp3                 # 可选：例句2音频
    /// ├── word2.mp3
    /// └── ...
    /// ```
    ///
    /// **文本文件格式（每行一个单词）：**
    /// ```
    /// 单词|发音|词性，词义|例句1|例句1翻译|例句2|例句2翻译|...
    /// ```
    /// - 最少3个字段（单词、发音、词义）
    /// - 例句和翻译成对出现（可以没有翻译）
    ///
    /// **示例行：**
    /// ```
    /// apple|/ˈæpl/|n. 苹果|I eat an apple.|我吃一个苹果。|The apple is red.|这个苹果是红色的。
    /// ```
    ///
    /// **执行流程：**
    /// 1. 解压ZIP到临时目录
    /// 2. 查找并验证txt文件
    /// 3. 检查同名词库是否已存在
    /// 4. 创建词库和音频目录
    /// 5. 逐行解析单词数据
    /// 6. 复制音频文件到Documents目录
    /// 7. 创建Word和WordState对象
    /// 8. 保存到SwiftData
    /// 9. 如果是第一个词库，自动设为当前词库
    /// 10. 自动关联已有习题集
    ///
    /// **重复处理策略：**
    /// - 同名词库：直接返回错误，不允许导入
    /// - 同名单词：跳过，计入duplicateCount
    ///
    /// **错误处理：**
    /// - 解压失败：返回错误信息
    /// - 找不到txt文件：返回错误信息
    /// - 单词格式错误：跳过该行，计入failedCount
    /// - 音频文件缺失：不影响导入，继续处理
    ///
    /// **性能考虑：**
    /// - 使用async/await处理ZIP解压（避免阻塞主线程）
    /// - 临时目录在方法结束时自动清理（defer）
    /// - 批量插入后一次性保存（减少数据库操作）
    func importFromZip(zipURL: URL, vocabularyName: String? = nil) async -> (vocabulary: Vocabulary?, result: ImportResult) {
        var result = ImportResult()

        // 创建临时目录用于解压（使用UUID避免冲突）
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // 确保方法结束时清理临时目录（无论成功或失败）
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 步骤1: 解压ZIP文件
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try await unzipFile(at: zipURL, to: tempDir)
        } catch {
            result.errorMessages.append("解压失败: \(error.localizedDescription)")
            return (nil, result)
        }

        // 步骤2: 查找文本文件（只支持.txt扩展名）
        let textFiles = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }

        guard let textFile = textFiles?.first else {
            result.errorMessages.append("未找到单词文本文件(.txt)")
            return (nil, result)
        }

        // 步骤3: 确定词库名称（优先使用参数，否则使用txt文件名）
        let finalVocabularyName = vocabularyName ?? textFile.deletingPathExtension().lastPathComponent

        // 步骤4: 检查是否已存在同名词库（不允许重复导入）
        let existingDescriptor = FetchDescriptor<Vocabulary>(
            predicate: #Predicate { $0.name == finalVocabularyName }
        )
        if (try? modelContext.fetch(existingDescriptor).first) != nil {
            result.errorMessages.append("词库'\(finalVocabularyName)'已存在")
            return (nil, result)
        }

        // 步骤5: 创建词库对象
        let vocabulary = Vocabulary(name: finalVocabularyName)
        modelContext.insert(vocabulary)

        // 步骤6: 创建音频目录（Documents/Audio/[词库名]/）
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioDestDir = documentsPath.appendingPathComponent("Audio/\(finalVocabularyName)")
        try? FileManager.default.createDirectory(at: audioDestDir, withIntermediateDirectories: true)

        // 步骤7: 读取文本文件内容
        guard let content = try? String(contentsOf: textFile, encoding: .utf8) else {
            result.errorMessages.append("无法读取文本文件")
            return (nil, result)
        }

        // 步骤8: 按行分割文本内容
        let lines = content.components(separatedBy: .newlines)

        // 步骤9: 遍历每一行，解析单词数据
        for (index, line) in lines.enumerated() {
            // 去除首尾空格
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            // 跳过空行
            if trimmedLine.isEmpty { continue }

            // 解析行格式: 单词|发音|词性，词义|例句1|例句1翻译|例句2|例句2翻译|...
            let parts = trimmedLine.components(separatedBy: "|")

            // 格式验证：至少需要3个字段（单词、发音、词义）
            guard parts.count >= 3 else {
                result.failedCount += 1
                result.errorMessages.append("第\(index + 1)行格式错误")
                continue
            }

            // 提取基本字段并去除空格
            let wordText = parts[0].trimmingCharacters(in: .whitespaces)
            let pronunciation = parts[1].trimmingCharacters(in: .whitespaces)
            let meaning = parts[2].trimmingCharacters(in: .whitespaces)

            // 检查单词是否已存在（同一词库内不允许重复单词）
            let existingWordDescriptor = FetchDescriptor<Word>(
                predicate: #Predicate { word in
                    word.word == wordText && word.vocabulary?.name == finalVocabularyName
                }
            )
            if let _ = try? modelContext.fetch(existingWordDescriptor).first {
                // 单词已存在，跳过并计入重复数
                result.duplicateCount += 1
                continue
            }

            // 创建单词对象
            let word = Word(word: wordText, pronunciation: pronunciation, meaning: meaning)
            word.vocabulary = vocabulary

            // 处理单词音频文件（如果ZIP包中包含）
            // 音频文件命名规则：[单词文本（空格替换为下划线）].mp3
            let audioName = audioFileName(for: wordText)
            let wordAudioPath = "Audio/\(finalVocabularyName)/\(audioName).mp3"
            let sourceAudioPath = tempDir.appendingPathComponent("\(audioName).mp3")

            // 如果ZIP包中有这个音频文件，复制到Documents目录
            if FileManager.default.fileExists(atPath: sourceAudioPath.path) {
                let destAudioPath = audioDestDir.appendingPathComponent("\(audioName).mp3")
                try? FileManager.default.copyItem(at: sourceAudioPath, to: destAudioPath)
                word.audioPath = wordAudioPath
            }
            // 如果没有音频文件，audioPath保持为nil（学习时会跳过音频播放）

            // 处理例句和翻译（从第4个字段开始，成对出现）
            // 格式：|例句1|翻译1|例句2|翻译2|...
            var examples: [Example] = []
            var exampleIndex = 1  // 用于例句音频文件命名（word_1.mp3, word_2.mp3）
            var i = 3  // 从第4个字段开始（索引3）

            while i < parts.count {
                // 获取例句文本
                let exampleText = parts[i].trimmingCharacters(in: .whitespaces)

                // 跳过空的例句字段
                if exampleText.isEmpty {
                    i += 1
                    continue
                }

                // 获取例句翻译（下一个字段）
                var translation: String? = nil
                if i + 1 < parts.count {
                    let translationText = parts[i + 1].trimmingCharacters(in: .whitespaces)
                    if !translationText.isEmpty {
                        translation = translationText
                    }
                    i += 2 // 跳过例句和翻译两个字段
                } else {
                    i += 1 // 只有例句没有翻译（到达行尾）
                }

                // 检查并复制例句音频文件
                // 命名规则：[单词]_[序号].mp3（如 according_to_1.mp3）
                var exampleAudioPath: String? = nil
                let exampleAudioFileName = "\(audioName)_\(exampleIndex).mp3"
                let sourceExampleAudioPath = tempDir.appendingPathComponent(exampleAudioFileName)

                if FileManager.default.fileExists(atPath: sourceExampleAudioPath.path) {
                    let destExampleAudioPath = audioDestDir.appendingPathComponent(exampleAudioFileName)
                    try? FileManager.default.copyItem(at: sourceExampleAudioPath, to: destExampleAudioPath)
                    exampleAudioPath = "Audio/\(finalVocabularyName)/\(exampleAudioFileName)"
                }

                // 创建例句对象
                examples.append(Example(text: exampleText, translation: translation, audio: exampleAudioPath))
                exampleIndex += 1
            }
            word.examples = examples

            // 为单词创建初始学习状态（状态：未学习）
            let state = WordState(status: .unlearned)
            state.word = word
            word.state = state

            // 插入到SwiftData上下文
            modelContext.insert(word)
            modelContext.insert(state)
            result.successCount += 1
        }

        // 步骤10: 批量保存所有单词和状态到数据库
        try? modelContext.save()

        // 步骤11: 如果是第一个导入的词库，自动设为当前词库
        let allVocabs = getAllVocabularies()
        if allVocabs.count == 1 {
            vocabulary.isSelected = true
            try? modelContext.save()
        }

        // 步骤12: 自动关联已有的习题集
        // 如果用户之前导入过习题，系统会自动将习题与新导入的词库关联
        let exerciseImportService = ExerciseImportService(modelContext: modelContext)
        exerciseImportService.autoLinkExercisesForVocabulary(vocabulary)

        return (vocabulary, result)
    }

    /// 解压ZIP文件（内部方法）
    ///
    /// - Parameters:
    ///   - sourceURL: ZIP文件的URL路径
    ///   - destinationURL: 解压目标目录
    /// - Throws: ZIP解压错误
    ///
    /// **实现方式：**
    /// - 使用ZIPUtility工具类（纯Swift实现）
    /// - 支持标准ZIP格式
    /// - 异步执行（使用async/await）
    private func unzipFile(at sourceURL: URL, to destinationURL: URL) async throws {
        // 委托给ZIPUtility处理ZIP解压
        try ZIPUtility.unzip(at: sourceURL, to: destinationURL)
    }

    // MARK: - 学习数据重置

    /// 重置词库的学习数据（保留词库和单词，清除学习进度）
    ///
    /// - Parameter vocabulary: 要重置的词库
    ///
    /// **重置内容：**
    /// 1. 所有单词状态（WordState）
    ///    - status 重置为 .unlearned（未学习）
    ///    - masteryCount 重置为 0
    ///    - lastReviewed 重置为 nil
    ///    - firstLearnedDate 重置为 nil
    ///    - lastReviewPassedDate 重置为 nil
    ///    - 当前session测试结果清空（testMode1Result等）
    /// 2. 复习队列状态
    ///    - queueEnteredAt 重置为 nil（移出复习队列）
    /// 3. 所有学习记录（StudyRecord）
    ///    - 物理删除所有StudyRecord对象
    ///
    /// **不会重置的内容：**
    /// - 词库本身（Vocabulary）
    /// - 单词数据（Word、发音、词义、例句）
    /// - 音频文件（保留在文件系统中）
    ///
    /// **使用场景：**
    /// - 用户想重新开始学习某个词库
    /// - 清除错误的学习记录
    /// - 重置学习进度用于测试
    ///
    /// **注意：**
    /// - 操作不可逆，调用前应该有确认对话框
    /// - 重置后所有学习统计数据会丢失
    func resetVocabularyData(_ vocabulary: Vocabulary) {
        for word in vocabulary.words {
            // 重置单词状态到初始值
            word.state?.status = .unlearned
            word.state?.masteryCount = 0
            word.state?.lastReviewed = nil
            word.state?.firstLearnedDate = nil        // 重置首次学习日期
            word.state?.lastReviewPassedDate = nil    // 重置复习通过日期
            word.state?.lastSessionFailed = false     // 重置优先选中标记
            word.state?.startNewSession()             // 清空当前session的测试结果
            word.queueEnteredAt = nil                 // 移出复习队列

            // 删除所有学习记录（物理删除）
            for record in word.studyRecords {
                modelContext.delete(record)
            }
        }

        // 批量保存所有变更
        try? modelContext.save()
    }

    /// 重置所有词库的学习数据
    ///
    /// **功能：**
    /// - 调用resetVocabularyData遍历所有词库
    /// - 清除所有词库的学习进度和记录
    ///
    /// **使用场景：**
    /// - 用户想完全重置应用，重新开始学习
    /// - 清除所有测试数据
    ///
    /// **注意：**
    /// - 操作不可逆，调用前应该有确认对话框
    /// - 会删除所有学习统计数据
    func resetAllData() {
        let allVocabularies = getAllVocabularies()
        for vocabulary in allVocabularies {
            resetVocabularyData(vocabulary)
        }
    }
}
