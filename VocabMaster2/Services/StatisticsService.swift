//
//  StatisticsService.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import SwiftData

/// 错误单词统计
struct WordErrorStat: Identifiable {
    var id: String { word.word }
    var word: Word
    var errorCount: Int
    var lastErrorDate: Date?
}

/// 学习统计
struct LearningStats {
    var totalLearningDays: Int = 0
    var todayDuration: Int = 0  // 秒
    var weekDuration: Int = 0   // 秒
    var topErrorWords: [WordErrorStat] = []
}

/// 统计服务
@MainActor
class StatisticsService {
    private var modelContext: ModelContext
    private let settings = AppSettings.shared

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 获取学习统计数据
    func getStatistics(for vocabulary: Vocabulary?) -> LearningStats {
        var stats = LearningStats()

        // 获取所有学习记录
        let descriptor = FetchDescriptor<StudyRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        guard let allRecords = try? modelContext.fetch(descriptor) else {
            return stats
        }

        // 学习天数 (去重日期)
        let calendar = Calendar.current
        let uniqueDays = Set(allRecords.map { calendar.startOfDay(for: $0.createdAt) })
        stats.totalLearningDays = uniqueDays.count

        // 今日学习时长
        let today = calendar.startOfDay(for: Date())
        stats.todayDuration = allRecords
            .filter { calendar.startOfDay(for: $0.createdAt) == today }
            .reduce(0) { $0 + $1.duration }

        // 本周学习时长
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        stats.weekDuration = allRecords
            .filter { $0.createdAt >= weekAgo }
            .reduce(0) { $0 + $1.duration }

        // 错误单词统计
        stats.topErrorWords = getTopErrorWords()

        return stats
    }

    /// 获取最易错单词
    func getTopErrorWords() -> [WordErrorStat] {
        let descriptor = FetchDescriptor<StudyRecord>(
            predicate: #Predicate { $0.result == false }
        )

        guard let failedRecords = try? modelContext.fetch(descriptor) else {
            return []
        }

        // 根据设置的时间范围过滤
        let calendar = Calendar.current
        let filteredRecords: [StudyRecord]

        switch settings.errorStatsPeriod {
        case .all:
            filteredRecords = failedRecords
        case .last7Days:
            let cutoffDate = calendar.date(byAdding: .day, value: -7, to: Date())!
            filteredRecords = failedRecords.filter { $0.createdAt >= cutoffDate }
        case .last30Days:
            let cutoffDate = calendar.date(byAdding: .day, value: -30, to: Date())!
            filteredRecords = failedRecords.filter { $0.createdAt >= cutoffDate }
        case .last90Days:
            let cutoffDate = calendar.date(byAdding: .day, value: -90, to: Date())!
            filteredRecords = failedRecords.filter { $0.createdAt >= cutoffDate }
        }

        // 按单词分组统计
        var wordErrors: [String: (word: Word, count: Int, lastDate: Date?)] = [:]

        for record in filteredRecords {
            guard let word = record.word else { continue }
            let key = word.word

            if var existing = wordErrors[key] {
                existing.count += 1
                if let lastDate = existing.lastDate, record.createdAt > lastDate {
                    existing.lastDate = record.createdAt
                } else if existing.lastDate == nil {
                    existing.lastDate = record.createdAt
                }
                wordErrors[key] = existing
            } else {
                wordErrors[key] = (word: word, count: 1, lastDate: record.createdAt)
            }
        }

        // 排序: 先按错误次数降序，再按最近错误时间排序
        let sorted = wordErrors.values.sorted { a, b in
            if a.count != b.count {
                return a.count > b.count
            }
            return (a.lastDate ?? .distantPast) > (b.lastDate ?? .distantPast)
        }

        // 取TopN
        return Array(sorted.prefix(settings.errorStatsTopN)).map { item in
            WordErrorStat(word: item.word, errorCount: item.count, lastErrorDate: item.lastDate)
        }
    }

    /// 格式化时长显示
    static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)秒"
        } else if seconds < 3600 {
            return "\(seconds / 60)分钟"
        } else {
            let hours = Double(seconds) / 3600.0
            return String(format: "%.1f小时", hours)
        }
    }
}
