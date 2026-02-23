//
//  WordRecognitionService.swift
//  VocabMaster2
//
//  Created on 2026/01/28.
//

import Foundation
import NaturalLanguage

/// 单词识别服务，用于从例句中提取目标单词
class WordRecognitionService {
    /// 从例句中提取目标单词的所有变形
    /// - Parameters:
    ///   - targetWord: 目标单词（原形）
    ///   - sentence: 例句
    /// - Returns: 包含位置和实际词形的数组
    func findWordOccurrences(targetWord: String, in sentence: String) -> [(range: Range<String.Index>, actualForm: String)] {
        var occurrences: [(range: Range<String.Index>, actualForm: String)] = []

        // 使用 NLTokenizer 进行分词
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = sentence

        // 创建词形还原器
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = sentence

        // 遍历所有 token
        tokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { tokenRange, _ in
            let token = String(sentence[tokenRange])

            // 获取 token 的词根
            var lemma: String? = nil
            tagger.enumerateTags(in: tokenRange, unit: .word, scheme: .lemma) { tag, _ in
                lemma = tag?.rawValue
                return true
            }

            // 如果词根匹配目标单词，或者直接匹配（不区分大小写）
            let tokenLower = token.lowercased()
            let targetLower = targetWord.lowercased()
            let lemmaLower = lemma?.lowercased()

            if tokenLower == targetLower || lemmaLower == targetLower {
                occurrences.append((range: tokenRange, actualForm: token))
            }

            return true
        }

        return occurrences
    }

    /// 将例句中的目标单词替换为空格占位符
    /// - Parameters:
    ///   - targetWord: 目标单词
    ///   - sentence: 例句
    /// - Returns: (处理后的例句, 正确答案)，如果找不到单词返回 nil
    func createClozeTest(targetWord: String, sentence: String) -> (processedSentence: String, correctAnswer: String)? {
        let occurrences = findWordOccurrences(targetWord: targetWord, in: sentence)

        guard let firstOccurrence = occurrences.first else {
            return nil
        }

        // 使用第一个出现的单词
        let answer = firstOccurrence.actualForm
        let blankLength = answer.count
        let blank = String(repeating: "_", count: blankLength)

        // 替换单词为下划线
        var processedSentence = sentence
        processedSentence.replaceSubrange(firstOccurrence.range, with: blank)

        return (processedSentence, answer)
    }

    /// 检查用户输入是否与正确答案匹配（不区分大小写）
    /// - Parameters:
    ///   - userInput: 用户输入
    ///   - correctAnswer: 正确答案
    /// - Returns: 是否匹配
    func checkAnswer(userInput: String, correctAnswer: String) -> Bool {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespaces)
        return trimmedInput.lowercased() == correctAnswer.lowercased()
    }
}
