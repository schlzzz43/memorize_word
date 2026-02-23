import Foundation
import SwiftData

/// 习题模型
@Model
final class Exercise {
    /// 唯一标识
    @Attribute(.unique) var id: UUID

    /// 目标单词（关联到Word.word字段）
    var targetWord: String

    /// 题目
    var question: String

    /// 选项A
    var optionA: String

    /// 选项B
    var optionB: String

    /// 选项C
    var optionC: String

    /// 选项D
    var optionD: String

    /// 正确答案 (A/B/C/D)
    var correctAnswer: String

    /// 解析
    var explanation: String

    /// 题型分类（词性辨析、时态填空等）
    var testCategory: String

    /// 创建时间
    var createdAt: Date

    /// 当前权重（用于概率选择，初始值100）
    var weight: Double

    /// 关联的习题集
    var exerciseSet: ExerciseSet?

    /// 关联的单词（可选，单词可能未导入）
    var word: Word?

    /// 答题记录（级联删除）
    @Relationship(deleteRule: .cascade, inverse: \ExerciseRecord.exercise)
    var records: [ExerciseRecord]

    init(id: UUID = UUID(),
         targetWord: String,
         question: String,
         optionA: String,
         optionB: String,
         optionC: String,
         optionD: String,
         correctAnswer: String,
         explanation: String,
         testCategory: String,
         weight: Double = 100.0,
         createdAt: Date = Date()) {
        self.id = id
        self.targetWord = targetWord
        self.question = question
        self.optionA = optionA
        self.optionB = optionB
        self.optionC = optionC
        self.optionD = optionD
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.testCategory = testCategory
        self.weight = weight
        self.createdAt = createdAt
        self.records = []
    }

    /// 获取所有选项
    var options: [String] {
        [optionA, optionB, optionC, optionD]
    }

    /// 获取正确答案的索引 (0-3)
    var correctAnswerIndex: Int? {
        switch correctAnswer.uppercased() {
        case "A": return 0
        case "B": return 1
        case "C": return 2
        case "D": return 3
        default: return nil
        }
    }
}
