//
//  TestMode.swift
//  VocabMaster2
//
//  Created on 2026/01/28.
//

import Foundation

/// 测试模式枚举
enum TestMode: Int, Codable, CaseIterable {
    case wordToMeaning = 1      // 看单词，选意思
    case meaningToWord = 2      // 看意思，选单词
    case audioToSpelling = 3    // 听音频，默单词
    case exampleToWord = 4      // 看例句，填单词

    var displayName: String {
        switch self {
        case .wordToMeaning: return "看单词，选意思"
        case .meaningToWord: return "看意思，选单词"
        case .audioToSpelling: return "听音频，默单词"
        case .exampleToWord: return "看例句，填单词"
        }
    }

    var iconName: String {
        switch self {
        case .wordToMeaning: return "text.word.spacing"
        case .meaningToWord: return "translate"
        case .audioToSpelling: return "speaker.wave.2"
        case .exampleToWord: return "text.quote"
        }
    }
}

/// 单个测试任务
struct TestTask: Identifiable {
    let id = UUID()
    let word: Word
    let mode: TestMode
    var result: Bool? = nil  // nil=未测试, true=通过, false=失败
    var fromDontKnow: Bool = false  // 是否来自"我不认识"按钮
    var userAnswer: String? = nil  // 用户的答案（错误时保存用于显示）
}
