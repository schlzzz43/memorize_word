//
//  StudyRecord.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import SwiftData

/// 学习类型枚举
enum StudyType: Int, Codable {
    case newLearning = 0   // 新学
    case review = 1        // 复习
    case randomTest = 2    // 随机测试

    var displayName: String {
        switch self {
        case .newLearning: return "新学"
        case .review: return "复习"
        case .randomTest: return "测试"
        }
    }
}

/// 学习记录模型
@Model
final class StudyRecord {
    /// 学习类型 (0=新学, 1=复习, 2=测试)
    private var typeRaw: Int

    /// 测试结果 (0=失败, 1=成功)
    var result: Bool

    /// 错误次数 (0-3)
    var errors: Int

    /// 学习时长 (秒) - 不包括详细页停留时间
    var duration: Int

    /// 创建时间
    var createdAt: Date

    /// 关联的单词
    var word: Word?

    /// 学习类型枚举属性
    var type: StudyType {
        get { StudyType(rawValue: typeRaw) ?? .newLearning }
        set { typeRaw = newValue.rawValue }
    }

    init(type: StudyType, result: Bool, errors: Int = 0, duration: Int = 0, createdAt: Date = Date()) {
        self.typeRaw = type.rawValue
        self.result = result
        self.errors = errors
        self.duration = duration
        self.createdAt = createdAt
    }
}
