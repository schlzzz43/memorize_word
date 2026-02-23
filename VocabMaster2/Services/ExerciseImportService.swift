import Foundation
import SwiftData

/// 习题导入结果
struct ExerciseImportResult {
    var successCount: Int = 0
    var failedCount: Int = 0
    var skippedCount: Int = 0
    var errorMessages: [String] = []
    var exerciseSetName: String = ""
}

@MainActor
class ExerciseImportService {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// 从TXT文件导入习题
    func importFromTxt(txtURL: URL, fileName: String) async -> ExerciseImportResult {
        var result = ExerciseImportResult()

        // 验证文件扩展名是.txt
        guard fileName.lowercased().hasSuffix(".txt") else {
            result.errorMessages.append("❌ 必须上传.txt文件")
            result.errorMessages.append("当前文件名: \(fileName)")
            return result
        }

        // 提取习题集名称（去掉.txt后缀）
        let setName = fileName.replacingOccurrences(of: ".txt", with: "", options: .caseInsensitive)
        result.exerciseSetName = setName

        // 读取文件内容
        guard let content = try? String(contentsOf: txtURL, encoding: .utf8) else {
            result.errorMessages.append("❌ 无法读取文件（请使用UTF-8编码）")
            return result
        }

        // 创建习题集
        let exerciseSet = ExerciseSet(name: setName)
        modelContext.insert(exerciseSet)

        // 逐行解析
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let lineNumber = index + 1

            // 跳过表头行（检测是否包含 "Question" 或 "Option A" 等关键字）
            if index == 0 && (trimmed.contains("Question|") || trimmed.contains("Option A|") || trimmed.contains("Correct Answer")) {
                continue
            }

            // 解析格式: Word|Question|A|B|C|D|Answer|Explanation|Category
            let parts = trimmed.components(separatedBy: "|")

            // 验证字段数量
            guard parts.count == 9 else {
                result.failedCount += 1
                result.errorMessages.append("第\(lineNumber)行: 格式错误（需要9个字段，实际\(parts.count)个）")
                continue
            }

            let targetWord = parts[0].trimmingCharacters(in: .whitespaces)
            let question = parts[1].trimmingCharacters(in: .whitespaces)
            let optionA = parts[2].trimmingCharacters(in: .whitespaces)
            let optionB = parts[3].trimmingCharacters(in: .whitespaces)
            let optionC = parts[4].trimmingCharacters(in: .whitespaces)
            let optionD = parts[5].trimmingCharacters(in: .whitespaces)
            let correctAnswer = parts[6].trimmingCharacters(in: .whitespaces).uppercased()
            let explanation = parts[7].trimmingCharacters(in: .whitespaces)
            let category = parts[8].trimmingCharacters(in: .whitespaces)

            // 验证所有字段不为空
            if targetWord.isEmpty || question.isEmpty || optionA.isEmpty || optionB.isEmpty ||
               optionC.isEmpty || optionD.isEmpty || correctAnswer.isEmpty ||
               explanation.isEmpty || category.isEmpty {
                result.failedCount += 1
                result.errorMessages.append("第\(lineNumber)行: 包含空字段")
                continue
            }

            // 验证答案格式
            guard ["A", "B", "C", "D"].contains(correctAnswer) else {
                result.failedCount += 1
                result.errorMessages.append("第\(lineNumber)行: Answer必须是A/B/C/D之一（当前: \(correctAnswer)）")
                continue
            }

            // 创建习题
            let exercise = Exercise(
                targetWord: targetWord,
                question: question,
                optionA: optionA,
                optionB: optionB,
                optionC: optionC,
                optionD: optionD,
                correctAnswer: correctAnswer,
                explanation: explanation,
                testCategory: category
            )

            // 关联到习题集
            exercise.exerciseSet = exerciseSet
            exerciseSet.exercises.append(exercise)

            // 尝试关联到已有单词
            let linked = linkExerciseToWord(exercise: exercise)
            if !linked {
                result.skippedCount += 1
            }

            modelContext.insert(exercise)
            result.successCount += 1
        }

        // 保存
        do {
            try modelContext.save()
        } catch {
            result.errorMessages.append("❌ 保存失败: \(error.localizedDescription)")
        }

        return result
    }

    /// 尝试将习题关联到已有单词
    @discardableResult
    private func linkExerciseToWord(exercise: Exercise) -> Bool {
        let targetWordValue = exercise.targetWord
        let descriptor = FetchDescriptor<Word>(
            predicate: #Predicate { $0.word == targetWordValue }
        )

        if let word = try? modelContext.fetch(descriptor).first {
            exercise.word = word
            return true
        }

        return false
    }

    /// 当导入新词库时，自动关联该词库的单词到已有习题
    func autoLinkExercisesForVocabulary(_ vocabulary: Vocabulary) {
        let descriptor = FetchDescriptor<Exercise>()
        guard let allExercises = try? modelContext.fetch(descriptor) else { return }

        var linkedCount = 0

        for word in vocabulary.words {
            let matchingExercises = allExercises.filter {
                $0.targetWord == word.word && $0.word == nil
            }

            for exercise in matchingExercises {
                exercise.word = word
                linkedCount += 1
            }
        }

        if linkedCount > 0 {
            try? modelContext.save()
        }
    }
}
