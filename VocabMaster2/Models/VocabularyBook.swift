//
//  VocabularyBook.swift
//  VocabMaster2
//
//  Created on 2026/02/18.
//

import Foundation
import SwiftData

/// 生词本模型
@Model
final class VocabularyBook {
    /// 生词本名称
    var name: String

    /// 是否为默认生词本
    var isDefault: Bool

    /// 创建时间
    var createdAt: Date

    /// 关联的单词列表
    @Relationship(deleteRule: .cascade, inverse: \VocabularyBookWord.vocabularyBook)
    var words: [VocabularyBookWord]

    init(name: String, isDefault: Bool = false, createdAt: Date = Date()) {
        self.name = name
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.words = []
    }

    /// 单词数量
    var wordCount: Int {
        words.count
    }
}
