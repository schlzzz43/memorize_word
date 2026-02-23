//
//  StudySessionManager.swift
//  VocabMaster2
//
//  Created on 2026/01/29.
//

import Foundation
import SwiftData
import CryptoKit

/// 学习会话管理器（负责保存和恢复学习进度）
@MainActor
class StudySessionManager {
    static let shared = StudySessionManager()

    private let userDefaultsKey = "savedStudySession"
    private let expirationHours: Double = 24 // 24小时过期

    private init() {}

    // MARK: - 保存会话

    /// 保存当前学习会话
    func saveSession(_ snapshot: StudySessionSnapshot) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(snapshot)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            // 保存失败（静默处理）
        }
    }

    // MARK: - 恢复会话

    /// 获取保存的会话（如果存在且未过期）
    func getSavedSession() -> StudySessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let snapshot = try decoder.decode(StudySessionSnapshot.self, from: data)

            // 检查是否过期
            let hoursSinceSaved = Date().timeIntervalSince(snapshot.savedAt) / 3600
            if hoursSinceSaved > expirationHours {
                clearSession()
                return nil
            }

            return snapshot
        } catch {
            clearSession() // 清除损坏的数据
            return nil
        }
    }

    /// 检查词汇表是否发生变更
    func isVocabularyChanged(savedHash: String, vocabulary: Vocabulary) -> Bool {
        let currentHash = calculateVocabularyHash(vocabulary)
        return savedHash != currentHash
    }

    // MARK: - 清除会话

    /// 清除保存的会话
    func clearSession() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - 辅助方法

    /// 计算词汇表的hash值（用于检测变更）
    func calculateVocabularyHash(_ vocabulary: Vocabulary) -> String {
        // 使用词汇表ID和单词数量作为简单hash
        // 如果需要更精确的检测，可以包含所有单词的ID
        let wordIds = vocabulary.words.map { "\($0.id)" }.sorted().joined()
        let hashString = "\(vocabulary.name)-\(vocabulary.words.count)-\(wordIds)"
        return hashString.md5Hash()
    }
}

// MARK: - String MD5 Extension

extension String {
    /// 计算字符串的SHA256 hash（用于检测词汇表变更）
    func md5Hash() -> String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
