//
//  StudyRecordExportService.swift
//  VocabMaster2
//
//  Created on 2026/01/27.
//

import Foundation
import SwiftData

/// 学习记录导出数据
struct StudyRecordExportData: Codable {
    var exportDate: Date
    var records: [ExportedRecord]
    var wordStates: [ExportedWordState]?  // 新增：单词状态数据（可选，兼容旧版）

    struct ExportedRecord: Codable {
        var word: String            // 单词文本
        var vocabularyName: String  // 所属词库名称
        var type: Int               // 学习类型 (0=新学, 1=复习, 2=测试)
        var result: Bool            // 测试结果
        var errors: Int             // 错误次数
        var duration: Int           // 学习时长（秒）
        var createdAt: Date         // 创建时间
    }

    struct ExportedWordState: Codable {
        var word: String            // 单词文本
        var vocabularyName: String  // 所属词库名称
        var status: Int             // 状态 (0=未学习, 1=待复习, 2=已掌握)
        var masteryCount: Int       // 掌握计数
        var lastReviewed: Date?     // 上次复习时间
        var queueEnteredAt: Date?   // 加入复习队列时间
        var firstLearnedDate: Date? // 首次学习日期（新增）
        var lastReviewPassedDate: Date? // 最后一次复习通过日期（新增）
        var createdAt: Date?        // WordState创建时间（新增，可选以兼容旧版）
    }
}

/// 学习记录导入导出服务
@MainActor
class StudyRecordExportService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 导出

    /// 导出所有学习记录到 JSON 文件
    /// - Returns: JSON 文件的 URL
    func exportAllRecords() throws -> URL {
        // 获取所有学习记录
        let recordDescriptor = FetchDescriptor<StudyRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let allRecords = try modelContext.fetch(recordDescriptor)

        // 转换为导出格式
        var exportedRecords: [StudyRecordExportData.ExportedRecord] = []

        for record in allRecords {
            guard let word = record.word else { continue }
            guard let vocabulary = word.vocabulary else { continue }

            let exportedRecord = StudyRecordExportData.ExportedRecord(
                word: word.word,
                vocabularyName: vocabulary.name,
                type: record.type.rawValue,
                result: record.result,
                errors: record.errors,
                duration: record.duration,
                createdAt: record.createdAt
            )

            exportedRecords.append(exportedRecord)
        }

        // 获取所有单词状态
        let wordDescriptor = FetchDescriptor<Word>()
        let allWords = try modelContext.fetch(wordDescriptor)

        var exportedWordStates: [StudyRecordExportData.ExportedWordState] = []

        for word in allWords {
            guard let vocabulary = word.vocabulary else { continue }
            guard let state = word.state else { continue }

            let exportedState = StudyRecordExportData.ExportedWordState(
                word: word.word,
                vocabularyName: vocabulary.name,
                status: state.status.rawValue,
                masteryCount: state.masteryCount,
                lastReviewed: state.lastReviewed,
                queueEnteredAt: word.queueEnteredAt,
                firstLearnedDate: state.firstLearnedDate,
                lastReviewPassedDate: state.lastReviewPassedDate,
                createdAt: state.createdAt
            )

            exportedWordStates.append(exportedState)
        }

        // 创建导出数据
        let exportData = StudyRecordExportData(
            exportDate: Date(),
            records: exportedRecords,
            wordStates: exportedWordStates.isEmpty ? nil : exportedWordStates
        )

        // 编码为 JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(exportData)

        // 保存到临时文件
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let fileName = "学习记录_\(dateString).json"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try jsonData.write(to: tempURL)

        return tempURL
    }

    // MARK: - 导入

    /// 从 JSON 文件导入学习记录
    /// - Parameter url: JSON 文件的 URL
    /// - Returns: 导入结果 (记录数量, 状态数量, 跳过数量)
    func importRecords(from url: URL) throws -> (records: Int, states: Int, skipped: Int) {
        // 读取 JSON 文件
        let jsonData = try Data(contentsOf: url)

        // 解码
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportData = try decoder.decode(StudyRecordExportData.self, from: jsonData)

        var importedCount = 0
        var skippedCount = 0

        // 获取所有词库，用于查找
        let vocabularies = try modelContext.fetch(FetchDescriptor<Vocabulary>())

        // 导入学习记录
        for exportedRecord in exportData.records {
            // 查找对应的词库
            guard let vocabulary = vocabularies.first(where: { $0.name == exportedRecord.vocabularyName }) else {
                skippedCount += 1
                continue
            }

            // 查找对应的单词
            guard let word = vocabulary.words.first(where: { $0.word == exportedRecord.word }) else {
                skippedCount += 1
                continue
            }

            // 检查是否已存在相同的记录（根据单词、类型和创建时间判断）
            let existingRecord = word.studyRecords.first {
                $0.type.rawValue == exportedRecord.type &&
                abs($0.createdAt.timeIntervalSince(exportedRecord.createdAt)) < 1.0
            }

            if existingRecord != nil {
                // 已存在，跳过
                skippedCount += 1
                continue
            }

            // 创建学习记录
            guard let studyType = StudyType(rawValue: exportedRecord.type) else {
                skippedCount += 1
                continue
            }

            let record = StudyRecord(
                type: studyType,
                result: exportedRecord.result,
                errors: exportedRecord.errors,
                duration: exportedRecord.duration,
                createdAt: exportedRecord.createdAt
            )
            record.word = word

            modelContext.insert(record)
            importedCount += 1
        }

        // 导入单词状态（如果有）
        var statesUpdated = 0
        if let wordStates = exportData.wordStates {
            for exportedState in wordStates {
                // 查找对应的词库
                guard let vocabulary = vocabularies.first(where: { $0.name == exportedState.vocabularyName }) else {
                    continue
                }

                // 查找对应的单词
                guard let word = vocabulary.words.first(where: { $0.word == exportedState.word }) else {
                    continue
                }

                // 获取或创建单词状态
                if let state = word.state {
                    // 更新现有状态
                    if let status = WordStatus(rawValue: exportedState.status) {
                        state.status = status
                    }
                    state.masteryCount = exportedState.masteryCount
                    state.lastReviewed = exportedState.lastReviewed
                    state.firstLearnedDate = exportedState.firstLearnedDate
                    state.lastReviewPassedDate = exportedState.lastReviewPassedDate
                    if let createdAt = exportedState.createdAt {
                        state.createdAt = createdAt
                    }
                    word.queueEnteredAt = exportedState.queueEnteredAt
                    statesUpdated += 1
                }
            }
        }

        // 保存
        try modelContext.save()

        return (records: importedCount, states: statesUpdated, skipped: skippedCount)
    }
}
