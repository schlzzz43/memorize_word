//
//  Word.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import SwiftData

/// 例句模型
struct Example: Codable, Hashable {
    /// 例句文本
    var text: String
    /// 例句翻译
    var translation: String?
    /// 例句音频路径
    var audio: String?
}

/// 单词模型
@Model
final class Word {
    /// 单词拼写
    var word: String

    /// 发音/音标
    var pronunciation: String

    /// 词性和词义
    var meaning: String

    /// 单词音频路径
    var audioPath: String?

    /// 例句列表 (JSON存储)
    var examplesData: Data?

    /// 创建时间
    var createdAt: Date

    /// 加入复习队列的时间 (用于FIFO排序)
    var queueEnteredAt: Date?

    /// 所属词库
    var vocabulary: Vocabulary?

    /// 单词状态
    @Relationship(deleteRule: .cascade, inverse: \WordState.word)
    var state: WordState?

    /// 学习记录
    @Relationship(deleteRule: .cascade, inverse: \StudyRecord.word)
    var studyRecords: [StudyRecord]

    init(word: String, pronunciation: String, meaning: String, audioPath: String? = nil, createdAt: Date = Date()) {
        self.word = word
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.audioPath = audioPath
        self.createdAt = createdAt
        self.studyRecords = []
    }

    /// 获取例句列表
    var examples: [Example] {
        get {
            guard let data = examplesData else { return [] }
            do {
                return try JSONDecoder().decode([Example].self, from: data)
            } catch {
                print("⚠️ [Word] JSON解码失败 - 单词: \(word), 错误: \(error.localizedDescription)")
                return []
            }
        }
        set {
            do {
                examplesData = try JSONEncoder().encode(newValue)
            } catch {
                print("⚠️ [Word] JSON编码失败 - 单词: \(word), 错误: \(error.localizedDescription)")
                examplesData = nil
            }
        }
    }

    /// 添加例句
    func addExample(text: String, translation: String? = nil, audio: String? = nil) {
        var currentExamples = examples
        currentExamples.append(Example(text: text, translation: translation, audio: audio))
        examples = currentExamples
    }
}
