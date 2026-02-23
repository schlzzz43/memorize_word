//
//  VocabularyBookWord.swift
//  VocabMaster2
//
//  Created on 2026/02/18.
//

import Foundation
import SwiftData

/// 生词本单词模型
@Model
final class VocabularyBookWord {
    /// 单词文本
    var word: String

    /// 添加时间
    var addedAt: Date

    /// 所属生词本
    var vocabularyBook: VocabularyBook?

    init(word: String, addedAt: Date = Date()) {
        self.word = word
        self.addedAt = addedAt
    }
}
