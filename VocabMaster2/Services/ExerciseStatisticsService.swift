//
//  ExerciseStatisticsService.swift
//  VocabMaster2
//
//  Created on 2026/02/15.
//

import Foundation
import SwiftData

/// 习题错误统计
struct ExerciseErrorStat: Identifiable {
    var id: UUID { exercise.id }
    var exercise: Exercise
    var errorCount: Int
    var lastErrorDate: Date?
}

/// 习题分类错误统计
struct CategoryErrorStat: Identifiable {
    var id: String { category }
    var category: String  // testCategory
    var errorCount: Int
    var totalCount: Int
    var errorRate: Double {
        totalCount > 0 ? Double(errorCount) / Double(totalCount) : 0
    }
}

/// 习题学习概况
struct ExerciseOverview {
    var totalExercises: Int = 0
    var attemptedExercises: Int = 0
    var totalAttempts: Int = 0
    var correctAttempts: Int = 0
    var correctRate: Double {
        totalAttempts > 0 ? Double(correctAttempts) / Double(totalAttempts) : 0
    }
}

/// 习题统计数据
struct ExerciseStats {
    var overview: ExerciseOverview = ExerciseOverview()
    var topErrorExercises: [ExerciseErrorStat] = []
    var categoryErrors: [CategoryErrorStat] = []
}

/// 习题统计服务
@MainActor
class ExerciseStatisticsService {
    private var modelContext: ModelContext
    private let settings = AppSettings.shared

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 获取习题统计数据
    func getStatistics() -> ExerciseStats {
        var stats = ExerciseStats()

        // 获取所有习题
        let exerciseDescriptor = FetchDescriptor<Exercise>()
        guard let allExercises = try? modelContext.fetch(exerciseDescriptor) else {
            return stats
        }

        // 获取所有答题记录
        let recordDescriptor = FetchDescriptor<ExerciseRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        guard let allRecords = try? modelContext.fetch(recordDescriptor) else {
            return stats
        }

        // 计算概况统计
        stats.overview = calculateOverview(exercises: allExercises, records: allRecords)

        // 计算错误习题统计
        stats.topErrorExercises = getTopErrorExercises(records: allRecords)

        // 计算分类错误统计
        stats.categoryErrors = getCategoryErrors(exercises: allExercises, records: allRecords)

        return stats
    }

    /// 计算习题概况
    private func calculateOverview(exercises: [Exercise], records: [ExerciseRecord]) -> ExerciseOverview {
        var overview = ExerciseOverview()

        overview.totalExercises = exercises.count

        // 计算已尝试的习题数（有答题记录的习题）
        let exercisesWithRecords = Set(records.compactMap { $0.exercise?.id })
        overview.attemptedExercises = exercisesWithRecords.count

        // 计算总答题次数和正确次数
        overview.totalAttempts = records.count
        overview.correctAttempts = records.filter { $0.isCorrect }.count

        return overview
    }

    /// 获取最易错习题
    private func getTopErrorExercises(records: [ExerciseRecord]) -> [ExerciseErrorStat] {
        // 筛选错误记录
        let failedRecords = records.filter { !$0.isCorrect }

        // 根据设置的时间范围过滤
        let filteredRecords = filterRecordsByPeriod(failedRecords)

        // 按习题分组统计
        var exerciseErrors: [UUID: (exercise: Exercise, count: Int, lastDate: Date?)] = [:]

        for record in filteredRecords {
            guard let exercise = record.exercise else { continue }
            let key = exercise.id

            if var existing = exerciseErrors[key] {
                existing.count += 1
                if let lastDate = existing.lastDate, record.createdAt > lastDate {
                    existing.lastDate = record.createdAt
                } else if existing.lastDate == nil {
                    existing.lastDate = record.createdAt
                }
                exerciseErrors[key] = existing
            } else {
                exerciseErrors[key] = (exercise: exercise, count: 1, lastDate: record.createdAt)
            }
        }

        // 排序: 先按错误次数降序，再按最近错误时间排序
        let sorted = exerciseErrors.values.sorted { a, b in
            if a.count != b.count {
                return a.count > b.count
            }
            return (a.lastDate ?? .distantPast) > (b.lastDate ?? .distantPast)
        }

        // 取TopN
        return Array(sorted.prefix(settings.errorStatsTopN)).map { item in
            ExerciseErrorStat(exercise: item.exercise, errorCount: item.count, lastErrorDate: item.lastDate)
        }
    }

    /// 获取分类错误统计
    private func getCategoryErrors(exercises: [Exercise], records: [ExerciseRecord]) -> [CategoryErrorStat] {
        // 根据时间范围过滤记录
        let filteredRecords = filterRecordsByPeriod(records)

        // 按题型分类统计
        var categoryStats: [String: (errorCount: Int, totalCount: Int)] = [:]

        for record in filteredRecords {
            guard let exercise = record.exercise else { continue }
            let category = exercise.testCategory

            if var existing = categoryStats[category] {
                existing.totalCount += 1
                if !record.isCorrect {
                    existing.errorCount += 1
                }
                categoryStats[category] = existing
            } else {
                categoryStats[category] = (errorCount: record.isCorrect ? 0 : 1, totalCount: 1)
            }
        }

        // 转换为数组并按错误率降序排序
        return categoryStats.map { key, value in
            CategoryErrorStat(category: key, errorCount: value.errorCount, totalCount: value.totalCount)
        }.sorted { $0.errorRate > $1.errorRate }
    }

    /// 根据设置的时间范围过滤记录
    private func filterRecordsByPeriod(_ records: [ExerciseRecord]) -> [ExerciseRecord] {
        let calendar = Calendar.current

        switch settings.errorStatsPeriod {
        case .all:
            return records
        case .last7Days:
            let cutoffDate = calendar.date(byAdding: .day, value: -7, to: Date())!
            return records.filter { $0.createdAt >= cutoffDate }
        case .last30Days:
            let cutoffDate = calendar.date(byAdding: .day, value: -30, to: Date())!
            return records.filter { $0.createdAt >= cutoffDate }
        case .last90Days:
            let cutoffDate = calendar.date(byAdding: .day, value: -90, to: Date())!
            return records.filter { $0.createdAt >= cutoffDate }
        }
    }

    /// 格式化百分比显示
    static func formatPercentage(_ rate: Double) -> String {
        return String(format: "%.1f%%", rate * 100)
    }
}
