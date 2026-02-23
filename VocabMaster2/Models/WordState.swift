//
//  WordState.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import SwiftData

/// 单词状态枚举
enum WordStatus: Int, Codable, CaseIterable {
    case unlearned = 0  // 未学习
    case reviewing = 1  // 待复习
    case mastered = 2   // 已掌握

    var displayName: String {
        switch self {
        case .unlearned: return "未学习"
        case .reviewing: return "待复习"
        case .mastered: return "已掌握"
        }
    }

    var iconName: String {
        switch self {
        case .unlearned: return "sparkle"
        case .reviewing: return "arrow.clockwise.circle"
        case .mastered: return "checkmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .unlearned: return "gray"
        case .reviewing: return "orange"
        case .mastered: return "green"
        }
    }
}

/// 单词状态模型
@Model
final class WordState {
    /// 状态值 (0=未学习, 1=待复习, 2=已掌握)
    private var statusRaw: Int

    /// 上次复习时间
    var lastReviewed: Date?

    /// 首次学习日期（从未学习转为待复习的日期）
    var firstLearnedDate: Date?

    /// 最后一次复习通过日期（reviewing/mastered状态下通过session的日期）
    var lastReviewPassedDate: Date?

    /// 创建时间
    var createdAt: Date

    /// 关联的单词
    var word: Word?

    /// 累计掌握计数（有多少个session所有测试都通过了）
    var masteryCount: Int

    /// 上次session是否答题失败（用于下次学习/复习时优先选中）
    var lastSessionFailed: Bool = false

    /// 当前session的测试结果（nil=未测试, true=通过, false=失败）
    var testMode1Result: Bool?
    var testMode2Result: Bool?
    var testMode3Result: Bool?
    var testMode4Result: Bool?

    /// 状态枚举属性
    var status: WordStatus {
        get { WordStatus(rawValue: statusRaw) ?? .unlearned }
        set { statusRaw = newValue.rawValue }
    }

    init(status: WordStatus = .unlearned, createdAt: Date = Date()) {
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.masteryCount = 0
        self.testMode1Result = nil
        self.testMode2Result = nil
        self.testMode3Result = nil
        self.testMode4Result = nil
    }

    /// 开始新的session，清空当前测试结果
    func startNewSession() {
        testMode1Result = nil
        testMode2Result = nil
        testMode3Result = nil
        testMode4Result = nil
    }

    /// 记录某个测试模式的结果
    func setTestResult(mode: TestMode, passed: Bool) {
        switch mode {
        case .wordToMeaning:
            testMode1Result = passed
        case .meaningToWord:
            testMode2Result = passed
        case .audioToSpelling:
            testMode3Result = passed
        case .exampleToWord:
            testMode4Result = passed
        }
        lastReviewed = Date()
    }

    /// 检查当前session是否所有启用的测试都已完成
    func areAllEnabledTestsCompleted(enabledModes: [TestMode]) -> Bool {
        for mode in enabledModes {
            switch mode {
            case .wordToMeaning:
                if testMode1Result == nil { return false }
            case .meaningToWord:
                if testMode2Result == nil { return false }
            case .audioToSpelling:
                if testMode3Result == nil { return false }
            case .exampleToWord:
                if testMode4Result == nil { return false }
            }
        }
        return true
    }

    /// 检查当前session是否所有启用的测试都通过了
    func didPassAllEnabledTests(enabledModes: [TestMode]) -> Bool {
        for mode in enabledModes {
            let result: Bool?
            switch mode {
            case .wordToMeaning:
                result = testMode1Result
            case .meaningToWord:
                result = testMode2Result
            case .audioToSpelling:
                result = testMode3Result
            case .exampleToWord:
                result = testMode4Result
            }

            if result != true {
                return false
            }
        }
        return true
    }

    /// Session结束时更新状态
    func onSessionCompleted(masteryThreshold: Int, enabledModes: [TestMode]) {
        let allPassed = didPassAllEnabledTests(enabledModes: enabledModes)

        if allPassed {
            // 所有测试通过
            if status == .unlearned {
                // 未学习 -> 待复习
                status = .reviewing
                word?.queueEnteredAt = Date()
                masteryCount = 1
                firstLearnedDate = Date()  // 记录首次学习日期
            } else if status == .reviewing {
                // 待复习状态，增加计数
                masteryCount += 1
                lastReviewPassedDate = Date()  // 记录复习通过日期

                // 检查是否达到已掌握阈值
                if masteryCount >= masteryThreshold {
                    status = .mastered
                    word?.queueEnteredAt = nil // 从复习队列移除
                }
            } else if status == .mastered {
                // 已掌握状态，保持并增加计数
                masteryCount += 1
                lastReviewPassedDate = Date()  // 记录复习通过日期（即使已掌握）
            }
        } else {
            // 有测试失败
            if status == .mastered {
                // 已掌握 -> 降级为待复习
                status = .reviewing
                word?.queueEnteredAt = Date()
                // masteryCount 保持不变（累计模式）
            }
            // 如果是待复习或未学习，状态不变
            // masteryCount 保持不变（累计模式）
        }

        // 记录本次session的失败状态，供下次学习/复习优先选中
        lastSessionFailed = !allPassed
    }

    /// 直接标记为已掌握（用于"直接掌握"按钮功能）
    func markAsMastered(masteryThreshold: Int) {
        status = .mastered
        masteryCount = masteryThreshold
        lastReviewed = Date()
        word?.queueEnteredAt = nil  // 从复习队列移除

        // 清空当前session的测试结果，保持状态一致性
        testMode1Result = nil
        testMode2Result = nil
        testMode3Result = nil
        testMode4Result = nil
    }
}
