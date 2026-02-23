//
//  DictationSession.swift
//  VocabMaster2
//
//  Created on 2026/02/11.
//

import Foundation
import Observation
import SwiftData

/// 听写会话模型
@Observable
class DictationSession {
    /// 听写的单词列表
    var words: [Word] = []

    /// 当前播放索引
    var currentIndex: Int = 0

    /// 用户的答案字典 (wordId -> answer)
    var answers: [PersistentIdentifier: String] = [:]

    /// 检查结果 (wordId -> correct)
    var results: [PersistentIdentifier: Bool] = [:]

    /// 是否已完成听写
    var isCompleted: Bool = false

    /// 是否已检查答案
    var isChecked: Bool = false

    /// 播放间隔（秒）
    var pauseDuration: Double = 3.0

    /// 重置会话
    func reset() {
        currentIndex = 0
        answers.removeAll()
        results.removeAll()
        isCompleted = false
        isChecked = false
    }

    /// 提交答案
    func submitAnswer(for wordId: PersistentIdentifier, answer: String) {
        answers[wordId] = answer
    }

    /// 检查所有答案
    func checkAnswers() {
        results.removeAll()
        for word in words {
            if let userAnswer = answers[word.id] {
                // 不区分大小写比较
                let correct = userAnswer.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    == word.word.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                results[word.id] = correct
            } else {
                results[word.id] = false
            }
        }
        isChecked = true
    }

    /// 获取正确数量
    var correctCount: Int {
        results.values.filter { $0 }.count
    }

    /// 获取总数
    var totalCount: Int {
        words.count
    }
}
