import Foundation
import SwiftData

/// 习题答题记录
@Model
final class ExerciseRecord {
    /// 用户答案 (A/B/C/D)
    var userAnswer: String

    /// 是否正确
    var isCorrect: Bool

    /// 答题时间
    var createdAt: Date

    /// 关联的习题
    var exercise: Exercise?

    init(userAnswer: String, isCorrect: Bool, createdAt: Date = Date()) {
        self.userAnswer = userAnswer
        self.isCorrect = isCorrect
        self.createdAt = createdAt
    }
}
