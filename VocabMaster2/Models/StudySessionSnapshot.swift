//
//  StudySessionSnapshot.swift
//  VocabMaster2
//
//  Created on 2026/01/29.
//

import Foundation
import SwiftData

/// 学习会话快照（用于保存和恢复进度）
struct StudySessionSnapshot: Codable {
    /// 学习模式
    let mode: StudyModeRaw

    /// 词汇表ID（使用字符串表示）
    let vocabularyId: String

    /// 任务列表
    let tasks: [TaskSnapshot]

    /// 当前任务索引
    let currentTaskIndex: Int

    /// 保存时间
    let savedAt: Date

    /// 词汇表内容hash（用于检测词汇表是否变更）
    let vocabularyHash: String
}

/// 单个任务的快照
struct TaskSnapshot: Codable {
    /// 单词ID（使用字符串表示）
    let wordId: String

    /// 测试模式
    let mode: TestMode

    /// 测试结果
    let result: Bool?

    /// 是否来自"我不认识"
    let fromDontKnow: Bool
}

/// StudyMode 的原始值表示（用于序列化）
enum StudyModeRaw: String, Codable {
    case newLearning
    case review
    case randomTest

    init(from mode: StudyMode) {
        switch mode {
        case .newLearning: self = .newLearning
        case .review: self = .review
        case .randomTest: self = .randomTest
        }
    }

    func toStudyMode() -> StudyMode {
        switch self {
        case .newLearning: return .newLearning
        case .review: return .review
        case .randomTest: return .randomTest
        }
    }
}
