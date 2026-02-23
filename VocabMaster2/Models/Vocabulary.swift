//
//  Vocabulary.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import SwiftData

/// 词库模型
@Model
final class Vocabulary {
    /// 词库名称 (唯一)
    @Attribute(.unique) var name: String

    /// 创建时间
    var createdAt: Date

    /// 是否为当前选中词库
    var isSelected: Bool

    /// 关联的单词列表
    @Relationship(deleteRule: .cascade, inverse: \Word.vocabulary)
    var words: [Word]

    init(name: String, createdAt: Date = Date(), isSelected: Bool = false) {
        self.name = name
        self.createdAt = createdAt
        self.isSelected = isSelected
        self.words = []
    }

    /// 未学习单词数量
    var unlearnedCount: Int {
        words.filter { $0.state?.status == .unlearned }.count
    }

    /// 待复习单词数量（所有状态为reviewing的单词）
    var reviewingCount: Int {
        words.filter { $0.state?.status == .reviewing }.count
    }

    /// 实际可复习单词数量（排除今天新学和今天复习通过的）
    var availableReviewingCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return words.filter { word in
            // 基本条件：状态为待复习
            guard let state = word.state else { return false }
            guard state.status == .reviewing else { return false }

            // 过滤条件1：排除今天新学的单词（firstLearnedDate是今天）
            if let firstLearned = state.firstLearnedDate {
                let learnedDay = calendar.startOfDay(for: firstLearned)
                if learnedDay == today {
                    return false  // 今天新学的，排除
                }
            }

            // 过滤条件2：排除今天复习通过的单词（lastReviewPassedDate是今天）
            if let lastPassed = state.lastReviewPassedDate {
                let passedDay = calendar.startOfDay(for: lastPassed)
                if passedDay == today {
                    return false  // 今天已复习通过，排除
                }
            }

            return true  // 通过所有过滤条件
        }.count
    }

    /// 已掌握单词数量
    var masteredCount: Int {
        words.filter { $0.state?.status == .mastered }.count
    }

    /// 总单词数量
    var totalCount: Int {
        words.count
    }
}
