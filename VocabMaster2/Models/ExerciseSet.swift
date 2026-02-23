import Foundation
import SwiftData

/// 习题集模型
@Model
final class ExerciseSet {
    /// 唯一标识
    @Attribute(.unique) var id: UUID

    /// 习题集名称（从文件名提取）
    var name: String

    /// 创建时间
    var createdAt: Date

    /// 习题列表（级联删除）
    @Relationship(deleteRule: .cascade, inverse: \Exercise.exerciseSet)
    var exercises: [Exercise]

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.exercises = []
    }
}
