import Foundation
import SwiftData

@MainActor
@Observable
class ExerciseService {
    private var modelContext: ModelContext
    private let settings = AppSettings.shared

    var currentExercises: [Exercise] = []
    var currentIndex: Int = 0
    var isCompleted: Bool = false
    var startTime: Date?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Exercise Selection with Weight System

    /// 开始答题会话（基于权重概率选择）
    func startExerciseSession(for exerciseSet: ExerciseSet) {
        let count = settings.exerciseCount

        // 获取该习题集中符合条件的习题
        let eligibleExercises = getEligibleExercises(from: exerciseSet)

        guard !eligibleExercises.isEmpty else {
            currentExercises = []
            isCompleted = true
            return
        }

        // 检查是否所有权重都< 5%（阈值）
        let maxWeight = eligibleExercises.map { $0.weight }.max() ?? 100.0
        if maxWeight < settings.exerciseResetThreshold {
            // 重置所有权重为初始值
            resetAllWeights(in: exerciseSet)
        }

        // 基于权重概率选择习题
        currentExercises = selectExercisesByWeight(from: eligibleExercises, count: count)
        currentIndex = 0
        isCompleted = currentExercises.isEmpty
        startTime = Date()
    }

    /// 获取符合条件的习题（单词状态为reviewing或mastered）
    private func getEligibleExercises(from exerciseSet: ExerciseSet) -> [Exercise] {
        return exerciseSet.exercises.filter { exercise in
            guard let word = exercise.word,
                  let status = word.state?.status else {
                return false
            }
            return status == .reviewing || status == .mastered
        }
    }

    /// 基于权重的概率选择算法
    private func selectExercisesByWeight(from exercises: [Exercise], count: Int) -> [Exercise] {
        var selected: [Exercise] = []
        var remaining = exercises
        var selectedWords = Set<String>() // 记录已选单词，避免同一单词出现多次

        for _ in 0..<min(count, exercises.count) {
            guard !remaining.isEmpty else { break }

            // 过滤掉已选单词的其他习题
            let availableExercises = remaining.filter { !selectedWords.contains($0.targetWord) }
            guard !availableExercises.isEmpty else { break }

            // 计算总权重
            let totalWeight = availableExercises.reduce(0.0) { $0 + $1.weight }

            // 随机选择（基于权重，使用增强的随机性）
            var random = RandomUtility.enhancedRandom(in: 0..<totalWeight)
            var selectedExercise: Exercise?

            for exercise in availableExercises {
                random -= exercise.weight
                if random <= 0 {
                    selectedExercise = exercise
                    break
                }
            }

            if let exercise = selectedExercise {
                selected.append(exercise)
                selectedWords.insert(exercise.targetWord)
                remaining.removeAll { $0.id == exercise.id }
            }
        }

        return selected.enhancedShuffled()
    }

    /// 处理答案
    func processAnswer(_ userAnswer: String, for exercise: Exercise) -> Bool {
        let isCorrect = (userAnswer.uppercased() == exercise.correctAnswer.uppercased())

        // 创建答题记录
        let record = ExerciseRecord(userAnswer: userAnswer.uppercased(), isCorrect: isCorrect)
        record.exercise = exercise
        exercise.records.append(record)
        modelContext.insert(record)

        // 更新权重
        if isCorrect {
            // 答对：权重减半
            exercise.weight = max(1.0, exercise.weight / 2.0)
        }
        // 答错：权重不变

        try? modelContext.save()

        return isCorrect
    }

    /// 重置指定习题集的所有习题权重
    func resetAllWeights(in exerciseSet: ExerciseSet) {
        for exercise in exerciseSet.exercises {
            exercise.weight = settings.exerciseInitialWeight
        }

        try? modelContext.save()
    }

    /// 移动到下一题
    func moveToNext() {
        if currentIndex < currentExercises.count - 1 {
            currentIndex += 1
        } else {
            isCompleted = true
        }
    }

    /// 当前习题
    var currentExercise: Exercise? {
        guard currentIndex < currentExercises.count else { return nil }
        return currentExercises[currentIndex]
    }

    /// 进度百分比
    var progress: Double {
        guard !currentExercises.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(currentExercises.count)
    }
}
