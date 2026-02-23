//
//  StudyService.swift
//  VocabMaster2
//
//  Created on 2026/01/28.
//

import Foundation
import SwiftData
import Combine

/// 学习模式枚举
///
/// 定义三种不同的学习模式，每种模式对应不同的单词选择策略和学习记录类型
enum StudyMode: Equatable {
    case newLearning    /// 学习新单词：从未学习状态的单词中选择
    case review         /// 复习旧单词：从复习队列中按FIFO顺序选择
    case randomTest     /// 随机测试：从所有词库的已掌握单词中随机抽取
}

/// 学习服务类
///
/// 核心业务逻辑服务，负责管理完整的单词学习流程。主要功能包括：
/// - 三种学习模式的会话启动和管理（新词学习、复习、随机测试）
/// - 支持4种测试模式组合（单词→词义、词义→单词、听力拼写、完形填空）
/// - 测试任务的生成、执行和结果处理
/// - 学习进度的保存和恢复
/// - 单词状态机的更新（未学习→待复习→已掌握）
/// - 学习记录的创建和持久化
///
/// **架构设计：**
/// - 使用MVVM模式，作为ViewModel层
/// - @MainActor保证所有操作在主线程执行，避免UI更新问题
/// - ObservableObject配合@Published属性实现响应式UI
///
/// **使用示例：**
/// ```swift
/// let service = StudyService(modelContext: context)
/// service.startNewLearning(vocabulary: vocab)
/// // 用户完成一个测试
/// service.processTestResult(passed: true)
/// service.moveToNext()
/// ```
@MainActor
class StudyService: ObservableObject {

    // MARK: - 依赖项

    /// SwiftData上下文，用于数据库操作
    private var modelContext: ModelContext

    /// 应用设置单例，获取用户配置（如每日学习数量、测试模式等）
    private let settings = AppSettings.shared

    /// 单词识别服务，用于生成完形填空测试
    private let wordRecognitionService = WordRecognitionService()

    // MARK: - 发布的状态属性

    /// 所有测试任务列表
    ///
    /// 每个单词根据启用的测试模式生成多个任务，所有任务随机打乱后存储在此数组中。
    /// UI通过观察此属性来显示总任务数和进度。
    @Published var testTasks: [TestTask] = []

    /// 当前任务索引
    ///
    /// 指向testTasks数组中当前正在进行的任务位置（从0开始）。
    /// 每次调用moveToNext()后会递增。
    @Published var currentTaskIndex: Int = 0

    /// 当前学习模式
    ///
    /// 决定单词选择策略和学习记录类型。在startNewLearning、startReview、startRandomTest时设置。
    @Published var currentMode: StudyMode = .newLearning

    /// 学习会话开始时间
    ///
    /// 用于计算总学习时长。在start*方法调用时设置为当前时间，
    /// 在completeSession时用于计算duration并平均分配到每个单词的StudyRecord中。
    @Published var startTime: Date?

    /// 会话是否已完成
    ///
    /// 当currentTaskIndex达到testTasks.count时设置为true，触发UI显示完成界面。
    @Published var isCompleted: Bool = false

    // MARK: - 私有状态

    /// 本次会话的单词列表（去重后的）
    ///
    /// 存储本次学习会话涉及的所有唯一单词对象。
    /// 用于计算totalWordCount和completedWordCount，以及在completeSession时批量更新状态。
    private var uniqueWords: [Word] = []

    // MARK: - 计算属性

    /// 当前测试任务
    ///
    /// 返回testTasks[currentTaskIndex]，如果索引越界返回nil。
    /// UI使用此属性获取当前要显示的单词和测试模式。
    var currentTask: TestTask? {
        guard currentTaskIndex < testTasks.count else { return nil }
        return testTasks[currentTaskIndex]
    }

    /// 学习进度（0.0 ~ 1.0）
    ///
    /// 计算公式：currentTaskIndex / testTasks.count
    /// 用于UI显示进度条。
    var progress: Double {
        guard !testTasks.isEmpty else { return 0 }
        return Double(currentTaskIndex) / Double(testTasks.count)
    }

    /// 剩余任务数量
    ///
    /// 计算还有多少个测试任务未完成。
    /// 用于UI显示剩余题目数。
    var remainingCount: Int {
        max(0, testTasks.count - currentTaskIndex)
    }

    /// 总单词数
    ///
    /// 返回本次会话涉及的唯一单词数量（不是任务数）。
    /// 例如：5个单词 x 4种测试模式 = 20个任务，但totalWordCount = 5
    var totalWordCount: Int {
        return uniqueWords.count
    }

    /// 已完成的单词数（所有模式都有结果的单词）
    ///
    /// 遍历uniqueWords，检查每个单词是否完成了所有启用的测试模式。
    /// 一个单词被认为"完成"需要满足：该单词的所有启用测试模式都有结果（passed/failed或fromDontKnow）。
    ///
    /// 用于UI显示已完成单词数，例如"已完成 3/5 个单词"。
    var completedWordCount: Int {
        let enabledModes = settings.enabledTestModes
        var completedCount = 0

        for word in uniqueWords {
            // 找到这个单词的所有任务
            let wordTasks = testTasks.filter { $0.word.id == word.id }
            // 筛选出已有结果的任务（测试完成或点了"我不认识"）
            let completedTasks = wordTasks.filter { $0.result != nil || $0.fromDontKnow }

            // 如果完成的任务数等于启用的模式数，说明这个单词的所有测试都做完了
            if completedTasks.count >= enabledModes.count {
                completedCount += 1
            }
        }

        return completedCount
    }

    // MARK: - 初始化

    /// 初始化学习服务
    ///
    /// - Parameter modelContext: SwiftData上下文，用于数据库读写操作
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 学习会话启动

    /// 开始学习新单词
    ///
    /// - Parameter vocabulary: 要学习的词库
    ///
    /// **执行流程：**
    /// 1. 从词库的未学习单词中随机选择N个（N = settings.dailyLearningCount）
    /// 2. 清空每个单词的session测试结果（调用startNewSession）
    /// 3. 为每个单词生成所有启用的测试模式任务并随机打乱
    /// 4. 初始化会话状态（currentTaskIndex=0, startTime=现在）
    ///
    /// **注意：**
    /// - 使用enhancedShuffled()增强随机性，避免伪随机导致的重复模式
    /// - 如果未学习单词不足N个，则选择所有可用单词
    /// - 如果没有未学习单词，testTasks为空，isCompleted立即设为true
    func startNewLearning(vocabulary: Vocabulary) {
        currentMode = .newLearning
        let count = settings.dailyLearningCount

        // 筛选出所有未学习状态的单词
        let unlearnedWords = vocabulary.words.filter { $0.state?.status == .unlearned }

        // 优先选择上次回答错误的单词，不足时随机补充其他单词
        let failedWords = unlearnedWords.filter { $0.state?.lastSessionFailed == true }.enhancedShuffled()
        let otherWords = unlearnedWords.filter { $0.state?.lastSessionFailed != true }.enhancedShuffled()
        let selectedWords = Array((failedWords + otherWords).prefix(count))

        // 保存单词列表，供后续计算进度和更新状态使用
        uniqueWords = selectedWords

        // 清空每个单词的当前session测试结果，准备新的测试
        for word in selectedWords {
            word.state?.startNewSession()
        }

        // 为每个单词生成所有启用的测试模式任务，并随机打乱顺序
        testTasks = generateTestTasks(for: selectedWords)
        currentTaskIndex = 0
        isCompleted = testTasks.isEmpty  // 如果没有单词可学，立即标记为完成
        startTime = Date()  // 记录开始时间，用于计算学习时长
    }

    /// 开始复习旧单词
    ///
    /// - Parameter vocabulary: 要复习的词库
    ///
    /// **单词选择策略（重要）：**
    /// 1. 基本条件：单词状态必须是 `.reviewing`（待复习）
    /// 2. 排除今天新学的单词：firstLearnedDate不是今天
    /// 3. 排除今天复习通过的单词：lastReviewPassedDate不是今天
    /// 4. 按FIFO顺序排序：根据queueEnteredAt升序，先进入队列的先复习
    /// 5. 取前N个单词（N = settings.dailyLearningCount）
    ///
    /// **为什么要排除今天新学和今天复习通过的单词？**
    /// - 避免用户在同一天反复复习同一批单词
    /// - 符合艾宾浩斯遗忘曲线，需要间隔一定时间再复习
    /// - 提升学习体验，每天都有新的内容
    ///
    /// **复习队列管理：**
    /// - 队列容量无限制（所有reviewing状态的单词都在队列中）
    /// - FIFO顺序保证公平性，不会有单词一直得不到复习
    /// - 单词从unlearned→reviewing时自动加入队列（设置queueEnteredAt）
    /// - 单词达到掌握阈值时从队列移除（queueEnteredAt设为nil）
    func startReview(vocabulary: Vocabulary) {
        currentMode = .review
        let count = settings.dailyLearningCount

        // 获取今天的起始时间（凌晨0点），用于日期比较
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 从复习队列中筛选符合条件的单词
        let reviewingWords = vocabulary.words
            .filter { word in
                // 基本条件：单词必须处于待复习状态
                guard let state = word.state else { return false }
                guard state.status == .reviewing else { return false }

                // 过滤条件1：排除今天新学的单词
                // 如果firstLearnedDate是今天，说明是今天刚从unlearned→reviewing，应该明天再复习
                if let firstLearned = state.firstLearnedDate {
                    let learnedDay = calendar.startOfDay(for: firstLearned)
                    if learnedDay == today {
                        return false  // 今天新学的，排除
                    }
                }

                // 过滤条件2：排除今天复习通过的单词
                // 如果lastReviewPassedDate是今天，说明今天已经复习并通过了，不应该再次出现
                if let lastPassed = state.lastReviewPassedDate {
                    let passedDay = calendar.startOfDay(for: lastPassed)
                    if passedDay == today {
                        return false  // 今天已复习通过，排除
                    }
                }

                return true  // 通过所有过滤条件
            }
            // 排序规则：上次回答错误的单词优先，同组内按FIFO顺序
            .sorted { word1, word2 in
                let failed1 = word1.state?.lastSessionFailed ?? false
                let failed2 = word2.state?.lastSessionFailed ?? false
                if failed1 != failed2 { return failed1 }  // 上次失败的排在前面
                // 同组内保持FIFO顺序（queueEnteredAt为nil的排在最后）
                return (word1.queueEnteredAt ?? .distantPast) < (word2.queueEnteredAt ?? .distantPast)
            }

        // 取前N个单词
        let selectedWords = Array(reviewingWords.prefix(count))

        // 保存单词列表
        uniqueWords = selectedWords

        // 清空每个单词的当前session测试结果
        for word in selectedWords {
            word.state?.startNewSession()
        }

        // 生成测试任务并随机打乱
        testTasks = generateTestTasks(for: selectedWords)
        currentTaskIndex = 0
        isCompleted = testTasks.isEmpty
        startTime = Date()
    }

    /// 开始随机测试（从所有词库的已掌握单词中抽取）
    ///
    /// - Parameter vocabulary: 当前词库（参数未使用，保留用于API一致性）
    ///
    /// **单词选择策略：**
    /// 1. 从**所有词库**（不仅是当前词库）中筛选已掌握单词（status = .mastered）
    /// 2. 随机抽取N个（N = settings.randomTestCount，默认10个）
    /// 3. 使用enhancedShuffled()增强随机性
    ///
    /// **为什么从所有词库选择？**
    /// - 随机测试是巩固记忆的手段，应该涵盖所有已掌握的单词
    /// - 避免长期不使用的词库单词被遗忘
    /// - 提供更大的单词池，增加测试的多样性
    ///
    /// **注意：**
    /// - 随机测试不会改变单词的masteryCount（掌握计数）
    /// - 但如果测试失败，单词会从mastered降级为reviewing
    func startRandomTest(vocabulary: Vocabulary) {
        currentMode = .randomTest
        let count = settings.randomTestCount

        // 获取所有词库
        let fetchDescriptor = FetchDescriptor<Vocabulary>()
        let allVocabularies = (try? modelContext.fetch(fetchDescriptor)) ?? []

        // 收集所有词库中的已掌握单词
        var allMasteredWords: [Word] = []
        for vocab in allVocabularies {
            let masteredWords = vocab.words.filter { $0.state?.status == .mastered }
            allMasteredWords.append(contentsOf: masteredWords)
        }

        // 随机抽取N个单词（使用增强的随机性）
        let selectedWords = Array(allMasteredWords.enhancedShuffled().prefix(count))

        // 保存单词列表
        uniqueWords = selectedWords

        // 清空每个单词的当前session测试结果
        for word in selectedWords {
            word.state?.startNewSession()
        }

        // 生成测试任务并随机打乱
        testTasks = generateTestTasks(for: selectedWords)
        currentTaskIndex = 0
        isCompleted = testTasks.isEmpty
        startTime = Date()
    }

    // MARK: - 测试任务生成

    /// 为选中的单词生成所有测试任务（随机顺序）
    ///
    /// - Parameter words: 要生成任务的单词列表
    /// - Returns: 所有测试任务的随机排列数组
    ///
    /// **生成策略：**
    /// 1. 为每个单词生成所有启用的测试模式任务（根据settings.enabledTestModes）
    /// 2. 例如：5个单词 x 4种测试模式 = 20个任务
    /// 3. 将所有任务完全随机打乱，避免连续出现同一单词或同一模式
    ///
    /// **为什么要随机打乱？**
    /// - 避免学习模式固定化（如先做所有单词的模式1，再做所有单词的模式2）
    /// - 增加测试难度和记忆强度
    /// - 更符合实际应用场景（随机遇到单词）
    private func generateTestTasks(for words: [Word]) -> [TestTask] {
        var tasks: [TestTask] = []
        let enabledModes = settings.enabledTestModes

        // 为每个单词生成所有启用的测试模式任务
        for word in words {
            for mode in enabledModes {
                tasks.append(TestTask(word: word, mode: mode))
            }
        }

        // 完全随机打乱所有任务（使用增强的随机性避免伪随机模式）
        return tasks.enhancedShuffled()
    }

    // MARK: - 测试结果处理

    /// 处理测试结果
    ///
    /// - Parameter passed: 测试是否通过
    ///
    /// **执行操作：**
    /// 1. 更新当前任务的result字段
    /// 2. 更新单词状态中对应测试模式的结果（testMode1Result等）
    /// 3. 更新单词的lastReviewed时间
    ///
    /// **注意：**
    /// - 此方法只更新内存中的状态，不立即保存数据库（避免主线程阻塞）
    /// - 最终的状态更新和持久化在completeSession()中批量完成
    func processTestResult(passed: Bool) {
        guard currentTaskIndex < testTasks.count else { return }
        var task = testTasks[currentTaskIndex]
        task.result = passed

        // 更新任务结果（struct是值类型，需要重新赋值）
        testTasks[currentTaskIndex] = task

        // 更新单词状态：记录此测试模式的结果，更新lastReviewed时间
        // 注意：不会立即改变单词的status，状态转换在completeSession中完成
        task.word.state?.setTestResult(mode: task.mode, passed: passed)
    }

    /// 处理"我不认识"按钮点击
    ///
    /// **业务语义：**
    /// "我不认识"在功能上等同于测试失败，但在UI和用户体验上有区别：
    /// - 用户主动承认不认识，而不是回答错误
    /// - 可以直接跳过测试，节省时间
    /// - 在统计中可以区分"不认识"和"答错"
    ///
    /// **执行操作：**
    /// 1. 标记任务的fromDontKnow为true（用于UI显示和统计）
    /// 2. 将测试结果设置为false（失败）
    /// 3. 更新单词状态（与processTestResult(false)效果相同）
    func processDontKnow() {
        guard currentTaskIndex < testTasks.count else { return }

        // 标记为"我不认识"，用于统计和UI区分
        testTasks[currentTaskIndex].fromDontKnow = true

        // "我不认识"等同于测试失败，将此测试模式标记为未通过
        let task = testTasks[currentTaskIndex]
        task.word.state?.setTestResult(mode: task.mode, passed: false)
    }

    /// 移动到下一个测试任务
    ///
    /// **行为：**
    /// - 如果还有剩余任务：递增currentTaskIndex
    /// - 如果是最后一个任务：调用completeSession()完成会话，设置isCompleted=true
    ///
    /// **注意：**
    /// - UI应该监听isCompleted属性来显示完成界面
    /// - completeSession()会批量更新所有单词状态并保存数据库
    func moveToNext() {
        if currentTaskIndex < testTasks.count - 1 {
            currentTaskIndex += 1
        } else {
            // 所有任务完成，批量更新单词状态、创建学习记录、保存数据库
            completeSession()
            isCompleted = true
        }
    }

    /// 跳过指定单词的剩余测试任务（点击"掌握"按钮时调用）
    ///
    /// - Parameter word: 要跳过剩余任务的单词
    ///
    /// **使用场景：**
    /// 用户在学习或复习过程中，对某个单词非常熟悉，希望直接标记为"掌握"，
    /// 跳过该单词的剩余测试模式，节省时间。
    ///
    /// **业务规则：**
    /// 1. 仅在newLearning和review模式下生效（randomTest模式禁用此功能）
    /// 2. 找到该单词在当前任务之后的所有剩余任务
    /// 3. 将这些任务从testTasks中删除
    /// 4. 将被跳过的测试模式标记为passed=true（确保completeSession时单词状态正确更新）
    ///
    /// **为什么要标记为passed？**
    /// - 如果不标记，completeSession时会认为这些测试失败（result为nil）
    /// - 导致单词的masteryCount不增加，甚至从mastered降级为reviewing
    /// - 标记为passed可确保单词按预期升级状态
    ///
    /// **实现细节：**
    /// - 使用reversed()遍历，确保删除元素时索引不变
    /// - 先收集所有要删除的索引和模式，再批量处理
    func skipRemainingTasksForWord(_ word: Word) {
        // 仅在学习新词和复习旧词模式下生效
        // 随机测试模式禁用此功能（因为随机测试的目的就是全面测试）
        guard currentMode == .newLearning || currentMode == .review else {
            return
        }

        // 找到当前任务之后的所有任务索引
        let nextIndex = currentTaskIndex + 1
        guard nextIndex < testTasks.count else { return }

        // 收集要删除的任务索引和对应的测试模式
        var indicesToRemove: [Int] = []
        var modesSkipped: [TestMode] = []

        // 从后往前遍历，避免删除元素时索引变化
        for i in (nextIndex..<testTasks.count).reversed() {
            if testTasks[i].word.id == word.id {
                indicesToRemove.append(i)
                modesSkipped.append(testTasks[i].mode)
            }
        }

        // 将被跳过的测试模式标记为passed=true
        // 这样在completeSession时，这些测试会被认为通过了
        for mode in modesSkipped {
            word.state?.setTestResult(mode: mode, passed: true)
        }

        // 从testTasks中删除这些任务
        for index in indicesToRemove {
            testTasks.remove(at: index)
        }
    }

    /// 完成学习会话，批量更新单词状态和创建学习记录
    ///
    /// **执行时机：**
    /// 在moveToNext()检测到所有任务完成时调用
    ///
    /// **核心功能：**
    /// 1. **更新单词状态**：调用WordState.onSessionCompleted更新status和masteryCount
    /// 2. **创建学习记录**：为每个单词创建StudyRecord，记录学习结果和时长
    /// 3. **持久化数据**：保存所有变更到数据库
    ///
    /// **状态转换逻辑（在WordState.onSessionCompleted中）：**
    /// - unlearned → reviewing：首次学习且所有测试通过
    /// - reviewing → mastered：复习通过且masteryCount >= masteryThreshold
    /// - mastered → reviewing：测试失败，降级
    ///
    /// **学习时长计算：**
    /// - 总时长 = 当前时间 - startTime
    /// - 单词时长 = 总时长 / 单词数量（平均分配）
    /// - 不包括详情页停留时间（详情页有单独的时长记录）
    ///
    /// **性能优化：**
    /// - 批量操作：一次性更新所有单词，一次性保存数据库
    /// - 减少主线程阻塞：不在每个测试后立即保存数据库
    private func completeSession() {
        // 从testTasks中提取所有唯一的单词对象（使用Set去重）
        let words = Set(testTasks.map { $0.word })
        let enabledModes = settings.enabledTestModes
        let masteryThreshold = settings.masteryThreshold

        // 计算会话总时长（秒）
        let sessionDuration = Int(Date().timeIntervalSince(startTime ?? Date()))
        // 平均分配到每个单词（如果有5个单词学了100秒，每个单词记录20秒）
        let durationPerWord = words.count > 0 ? sessionDuration / words.count : 0

        // 确定学习类型（用于创建StudyRecord）
        let studyType: StudyType = {
            switch currentMode {
            case .newLearning: return .newLearning
            case .review: return .review
            case .randomTest: return .randomTest
            }
        }()

        // 遍历所有单词，更新状态并创建学习记录
        for word in words {
            // 更新单词状态（unlearned→reviewing、reviewing→mastered等）
            // 内部会根据测试结果更新status、masteryCount、firstLearnedDate等字段
            word.state?.onSessionCompleted(
                masteryThreshold: masteryThreshold,
                enabledModes: enabledModes
            )

            // 创建学习记录
            guard let wordState = word.state else { continue }

            // 判断本次会话是否通过（所有启用的测试模式都通过）
            let passed = wordState.didPassAllEnabledTests(enabledModes: enabledModes)

            // 计算错误次数（有多少个测试模式结果为false）
            var errorCount = 0
            for mode in enabledModes {
                // 根据测试模式获取对应的结果
                let result: Bool?
                switch mode {
                case .wordToMeaning:
                    result = wordState.testMode1Result
                case .meaningToWord:
                    result = wordState.testMode2Result
                case .audioToSpelling:
                    result = wordState.testMode3Result
                case .exampleToWord:
                    result = wordState.testMode4Result
                }

                // 如果结果为false（测试失败），错误次数+1
                if result == false {
                    errorCount += 1
                }
            }

            // 创建StudyRecord对象
            let record = StudyRecord(
                type: studyType,           // 学习类型（新学/复习/测试）
                result: passed,            // 是否通过（所有测试都通过才为true）
                errors: errorCount,        // 错误的测试模式数量
                duration: durationPerWord, // 学习时长（秒）
                createdAt: Date()          // 创建时间（用于今日学习统计）
            )

            // 建立关系：record.word = word, word.studyRecords.append(record)
            record.word = word
            word.studyRecords.append(record)

            // 将StudyRecord插入到SwiftData上下文
            modelContext.insert(record)
        }

        // 批量保存所有变更到数据库（包括WordState更新和StudyRecord插入）
        try? modelContext.save()
    }

    // MARK: - 测试选项生成

    /// 生成词义选择题的选项（包含正确答案）
    ///
    /// - Parameters:
    ///   - word: 目标单词
    ///   - vocabulary: 词库（用于获取干扰项）
    /// - Returns: 包含正确答案和干扰项的选项数组（已随机打乱）
    ///
    /// **用于测试模式：** wordToMeaning（看单词选词义）
    ///
    /// **生成策略：**
    /// 1. 正确答案：word.meaning
    /// 2. 干扰项：从同一词库的其他单词中随机选择meaning作为干扰项
    /// 3. 选项总数：min(词库总数, 4)，如果词库只有2个单词，则只生成2个选项
    /// 4. 随机打乱所有选项（包括正确答案），避免正确答案总在固定位置
    ///
    /// **为什么干扰项要从同一词库选择？**
    /// - 确保难度适中，避免完全不相关的词义
    /// - 符合学习场景，用户正在学习这个词库的单词
    func generateMeaningOptions(for word: Word, from vocabulary: Vocabulary) -> [String] {
        var options: [String] = [word.meaning]

        // 筛选出其他单词（排除当前单词）
        let otherWords = vocabulary.words.filter { $0.word != word.word }

        // 计算选项总数：最多4个，但不能超过词库总单词数
        let totalWords = vocabulary.words.count
        let maxOptions = min(totalWords, 4)

        // 需要的干扰项数量 = 总选项数 - 1（正确答案）
        let distractorCount = maxOptions - 1
        // 随机选择干扰项（使用增强的随机性）
        let distractors = otherWords.enhancedShuffled().prefix(distractorCount).map { $0.meaning }

        options.append(contentsOf: distractors)

        // 随机打乱所有选项，避免正确答案总在第一个位置
        return options.enhancedShuffled()
    }

    /// 生成单词选择题的选项（包含正确答案）
    ///
    /// - Parameters:
    ///   - word: 目标单词
    ///   - vocabulary: 词库（用于获取干扰项）
    /// - Returns: 包含正确答案和干扰项的选项数组（已随机打乱）
    ///
    /// **用于测试模式：** meaningToWord（看词义选单词）
    ///
    /// **生成策略：**
    /// 与generateMeaningOptions相同，但选项内容为word.word而非word.meaning
    func generateWordOptions(for word: Word, from vocabulary: Vocabulary) -> [String] {
        var options: [String] = [word.word]

        // 筛选出其他单词
        let otherWords = vocabulary.words.filter { $0.word != word.word }

        // 计算选项总数
        let totalWords = vocabulary.words.count
        let maxOptions = min(totalWords, 4)

        // 需要的干扰项数量
        let distractorCount = maxOptions - 1
        let distractors = otherWords.enhancedShuffled().prefix(distractorCount).map { $0.word }

        options.append(contentsOf: distractors)

        return options.enhancedShuffled()
    }

    // MARK: - 拼写和完形填空

    /// 检查用户输入的拼写是否正确
    ///
    /// - Parameters:
    ///   - input: 用户输入的拼写
    ///   - word: 正确的单词对象
    /// - Returns: 拼写是否正确
    ///
    /// **用于测试模式：** audioToSpelling（听音频拼写）
    ///
    /// **匹配规则：**
    /// - 去除首尾空格后比较
    /// - **不区分大小写**（英语单词，lowercased()比较）
    /// - 完全匹配才算正确
    ///
    /// **示例：**
    /// - "Apple" == "apple" ✅
    /// - " apple " == "apple" ✅
    /// - "aple" == "apple" ❌
    func checkSpelling(input: String, word: Word) -> Bool {
        let correctWord = word.word.trimmingCharacters(in: .whitespaces)
        let inputWord = input.trimmingCharacters(in: .whitespaces)

        // 英语单词不区分大小写
        return inputWord.lowercased() == correctWord.lowercased()
    }

    /// 为单词准备完形填空测试
    ///
    /// - Parameter word: 目标单词
    /// - Returns: (处理后的例句, 正确答案, 原始例句, 例句翻译)，如果没有可用例句返回 nil
    ///
    /// **用于测试模式：** exampleToWord（完形填空）
    ///
    /// **执行流程：**
    /// 1. 检查单词是否有例句，如果没有返回nil
    /// 2. 从例句列表中随机选择一个例句
    /// 3. 调用WordRecognitionService.createClozeTest，使用NLP识别单词在句子中的形式
    /// 4. 将识别到的单词替换为下划线"______"
    /// 5. 返回处理后的句子、正确答案（识别到的原始形式）、原句、翻译
    ///
    /// **为什么需要NLP识别？**
    /// - 单词在句子中可能有不同形式（时态、复数等）
    /// - 例如："eat"在句子中可能是"eating", "ate", "eaten"
    /// - NLP可以识别并提取正确的形式作为答案
    ///
    /// **示例：**
    /// - 单词：run
    /// - 例句："He is running in the park."
    /// - 处理后："He is ______ in the park."
    /// - 正确答案："running"（而不是"run"）
    func prepareClozeTest(for word: Word) -> (processedSentence: String, correctAnswer: String, originalSentence: String, translation: String?)? {
        guard !word.examples.isEmpty else { return nil }

        // 从例句列表中随机选择一个（使用增强的随机性）
        let example = word.examples.enhancedRandomElement()!
        let sentence = example.text

        // 使用NLP服务识别单词在句子中的形式并生成填空题
        // createClozeTest会返回处理后的句子（单词替换为______）和正确答案
        if let result = wordRecognitionService.createClozeTest(targetWord: word.word, sentence: sentence) {
            return (result.processedSentence, result.correctAnswer, sentence, example.translation)
        }

        return nil
    }

    /// 检查完形填空答案是否正确
    ///
    /// - Parameters:
    ///   - userInput: 用户输入的答案
    ///   - correctAnswer: 正确答案（从prepareClozeTest返回的correctAnswer）
    /// - Returns: 答案是否正确
    ///
    /// **匹配规则：**
    /// - 委托给WordRecognitionService.checkAnswer处理
    /// - 通常是去除空格、不区分大小写的比较
    func checkClozeAnswer(userInput: String, correctAnswer: String) -> Bool {
        return wordRecognitionService.checkAnswer(userInput: userInput, correctAnswer: correctAnswer)
    }

    // MARK: - 会话保存和恢复

    /// 创建会话快照（用于保存当前学习进度）
    ///
    /// - Parameter vocabulary: 当前词库
    /// - Returns: 包含所有会话状态的快照对象
    ///
    /// **使用场景：**
    /// - 用户退出App时自动保存进度
    /// - 用户在学习中途切换到其他页面
    ///
    /// **保存内容：**
    /// 1. 学习模式（newLearning/review/randomTest）
    /// 2. 词库ID（用于恢复时验证词库是否还存在）
    /// 3. 所有测试任务及其结果（wordId, mode, result, fromDontKnow）
    /// 4. 当前任务索引（恢复到用户离开时的位置）
    /// 5. 保存时间（用作会话开始时间）
    /// 6. 词库哈希值（用于检测词库是否被修改）
    ///
    /// **词库哈希值的作用：**
    /// - 检测词库内容是否发生变化（单词增删、顺序变化等）
    /// - 如果哈希值不匹配，恢复会失败（避免数据不一致）
    func createSnapshot(vocabulary: Vocabulary) -> StudySessionSnapshot {
        // 将所有测试任务转换为快照格式（只保存必要字段）
        let taskSnapshots = testTasks.map { task in
            TaskSnapshot(
                wordId: "\(task.word.id)",   // Word对象的ID转为字符串
                mode: task.mode,               // 测试模式
                result: task.result,           // 测试结果（可能为nil）
                fromDontKnow: task.fromDontKnow // 是否点了"我不认识"
            )
        }

        // 计算词库的哈希值（基于单词内容和顺序）
        let vocabularyHash = StudySessionManager.shared.calculateVocabularyHash(vocabulary)

        // 创建快照对象
        return StudySessionSnapshot(
            mode: StudyModeRaw(from: currentMode),  // 学习模式
            vocabularyId: "\(vocabulary.id)",        // 词库ID
            tasks: taskSnapshots,                    // 所有任务快照
            currentTaskIndex: currentTaskIndex,      // 当前进度
            savedAt: Date(),                         // 保存时间
            vocabularyHash: vocabularyHash           // 词库哈希值
        )
    }

    /// 从快照恢复会话
    ///
    /// - Parameters:
    ///   - snapshot: 会话快照对象
    ///   - vocabulary: 当前词库
    /// - Returns: 是否成功恢复
    ///
    /// **恢复流程：**
    /// 1. 从快照中提取学习模式
    /// 2. 遍历任务快照，根据wordId从词库中查找对应的Word对象
    /// 3. 重建TestTask对象，恢复result和fromDontKnow状态
    /// 4. 重建uniqueWords列表（去重）
    /// 5. 恢复currentTaskIndex和startTime
    ///
    /// **失败情况：**
    /// - 快照中的单词在当前词库中找不到（词库被修改）
    /// - 所有任务都无法恢复（restoredTasks为空）
    ///
    /// **注意：**
    /// - startTime使用快照的savedAt而不是当前时间，这样学习时长计算才正确
    /// - currentTaskIndex可能因为任务数量变化而被裁剪到合法范围
    func restoreFromSnapshot(_ snapshot: StudySessionSnapshot, vocabulary: Vocabulary) -> Bool {
        // 设置学习模式
        currentMode = snapshot.mode.toStudyMode()

        // 重建任务列表和单词列表
        var restoredTasks: [TestTask] = []
        var restoredWords: [Word] = []

        for taskSnapshot in snapshot.tasks {
            // 根据wordId查找对应的Word对象
            guard let word = vocabulary.words.first(where: { "\($0.id)" == taskSnapshot.wordId }) else {
                // 如果找不到单词（可能词库被修改），跳过这个任务
                continue
            }

            // 重建TestTask对象
            var task = TestTask(word: word, mode: taskSnapshot.mode)
            task.result = taskSnapshot.result           // 恢复测试结果
            task.fromDontKnow = taskSnapshot.fromDontKnow  // 恢复"我不认识"标记
            restoredTasks.append(task)

            // 收集唯一的单词（用于uniqueWords）
            if !restoredWords.contains(where: { $0.id == word.id }) {
                restoredWords.append(word)
            }
        }

        // 如果没有成功恢复任何任务，返回失败
        guard !restoredTasks.isEmpty else {
            return false
        }

        // 应用恢复的数据到当前服务状态
        testTasks = restoredTasks
        uniqueWords = restoredWords
        // 确保currentTaskIndex在合法范围内（任务数量可能变化）
        currentTaskIndex = min(snapshot.currentTaskIndex, testTasks.count - 1)
        isCompleted = currentTaskIndex >= testTasks.count
        // 使用快照保存时间作为会话开始时间，保证学习时长计算正确
        startTime = snapshot.savedAt

        return true
    }
}

// MARK: - StudyMode 扩展

extension StudyMode {
    /// 转换为StudyType枚举（用于创建StudyRecord）
    ///
    /// StudyMode和StudyType的值是一一对应的，
    /// 这个计算属性提供便捷的转换方法。
    var studyType: StudyType {
        switch self {
        case .newLearning: return .newLearning
        case .review: return .review
        case .randomTest: return .randomTest
        }
    }

    /// 学习模式的显示名称（用于UI展示）
    var displayName: String {
        switch self {
        case .newLearning: return "学习新单词"
        case .review: return "复习旧单词"
        case .randomTest: return "随机测试"
        }
    }
}
