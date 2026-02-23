//
//  AppSettings.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import SwiftUI
import Combine

/// 错误统计周期
enum ErrorStatsPeriod: Int, CaseIterable, Codable {
    case all = 0
    case last7Days = 7
    case last30Days = 30
    case last90Days = 90

    var displayName: String {
        switch self {
        case .all: return "全部历史"
        case .last7Days: return "最近7天"
        case .last30Days: return "最近30天"
        case .last90Days: return "最近90天"
        }
    }
}

/// 主题模式
enum ThemeMode: String, CaseIterable, Codable {
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .light: return "白天"
        case .dark: return "黑夜"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// App设置管理类
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - 设置项Keys
    private enum Keys {
        static let dailyLearningCount = "dailyLearningCount"
        static let randomTestCount = "randomTestCount"
        static let masteryThreshold = "masteryThreshold"
        static let errorStatsTopN = "errorStatsTopN"
        static let errorStatsPeriod = "errorStatsPeriod"
        static let themeMode = "themeMode"
        static let autoPlayAudio = "autoPlayAudio"
        static let showPronunciation = "showPronunciation"
        static let exampleDisplayCount = "exampleDisplayCount"
        static let currentVocabularyId = "currentVocabularyId"
        static let testMode1Enabled = "testMode1Enabled"
        static let testMode2Enabled = "testMode2Enabled"
        static let testMode3Enabled = "testMode3Enabled"
        static let testMode4Enabled = "testMode4Enabled"
        // 习题相关
        static let exerciseCount = "exerciseCount"
        static let exerciseInitialWeight = "exerciseInitialWeight"
        static let exerciseResetThreshold = "exerciseResetThreshold"
    }

    // MARK: - 设置项

    /// 每日学习数量 (默认20, 范围5-100)
    @Published var dailyLearningCount: Int {
        didSet { defaults.set(dailyLearningCount, forKey: Keys.dailyLearningCount) }
    }

    /// 随机测试数量 (默认10, 范围5-50)
    @Published var randomTestCount: Int {
        didSet { defaults.set(randomTestCount, forKey: Keys.randomTestCount) }
    }

    /// 已掌握阈值N (默认3, 范围1-10)
    @Published var masteryThreshold: Int {
        didSet { defaults.set(masteryThreshold, forKey: Keys.masteryThreshold) }
    }

    /// 错误统计TopN (默认10, 范围5-20)
    @Published var errorStatsTopN: Int {
        didSet { defaults.set(errorStatsTopN, forKey: Keys.errorStatsTopN) }
    }

    /// 错误统计周期
    @Published var errorStatsPeriod: ErrorStatsPeriod {
        didSet { defaults.set(errorStatsPeriod.rawValue, forKey: Keys.errorStatsPeriod) }
    }

    /// 主题模式
    @Published var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }

    /// 自动播放音频
    @Published var autoPlayAudio: Bool {
        didSet { defaults.set(autoPlayAudio, forKey: Keys.autoPlayAudio) }
    }

    /// 显示音标
    @Published var showPronunciation: Bool {
        didSet { defaults.set(showPronunciation, forKey: Keys.showPronunciation) }
    }

    /// 例句显示数量 (1-5)
    @Published var exampleDisplayCount: Int {
        didSet { defaults.set(exampleDisplayCount, forKey: Keys.exampleDisplayCount) }
    }

    /// 当前词库ID
    @Published var currentVocabularyId: String? {
        didSet { defaults.set(currentVocabularyId, forKey: Keys.currentVocabularyId) }
    }

    /// 测试模式开关
    @Published var testMode1Enabled: Bool {
        didSet {
            defaults.set(testMode1Enabled, forKey: Keys.testMode1Enabled)
            ensureAtLeastOneTestModeEnabled()
        }
    }

    @Published var testMode2Enabled: Bool {
        didSet {
            defaults.set(testMode2Enabled, forKey: Keys.testMode2Enabled)
            ensureAtLeastOneTestModeEnabled()
        }
    }

    @Published var testMode3Enabled: Bool {
        didSet {
            defaults.set(testMode3Enabled, forKey: Keys.testMode3Enabled)
            ensureAtLeastOneTestModeEnabled()
        }
    }

    @Published var testMode4Enabled: Bool {
        didSet {
            defaults.set(testMode4Enabled, forKey: Keys.testMode4Enabled)
            ensureAtLeastOneTestModeEnabled()
        }
    }

    // MARK: - 习题设置

    /// 每次习题数量 (默认10, 范围5-50)
    @Published var exerciseCount: Int {
        didSet { defaults.set(exerciseCount, forKey: Keys.exerciseCount) }
    }

    /// 习题初始权重 (默认100)
    @Published var exerciseInitialWeight: Double {
        didSet { defaults.set(exerciseInitialWeight, forKey: Keys.exerciseInitialWeight) }
    }

    /// 权重重置阈值百分比 (默认5.0)
    @Published var exerciseResetThreshold: Double {
        didSet { defaults.set(exerciseResetThreshold, forKey: Keys.exerciseResetThreshold) }
    }

    private init() {
        // 加载设置或使用默认值
        self.dailyLearningCount = defaults.object(forKey: Keys.dailyLearningCount) as? Int ?? 20
        self.randomTestCount = defaults.object(forKey: Keys.randomTestCount) as? Int ?? 10
        self.masteryThreshold = defaults.object(forKey: Keys.masteryThreshold) as? Int ?? 3
        self.errorStatsTopN = defaults.object(forKey: Keys.errorStatsTopN) as? Int ?? 10

        if let periodRaw = defaults.object(forKey: Keys.errorStatsPeriod) as? Int,
           let period = ErrorStatsPeriod(rawValue: periodRaw) {
            self.errorStatsPeriod = period
        } else {
            self.errorStatsPeriod = .all
        }

        if let themeModeRaw = defaults.string(forKey: Keys.themeMode),
           let mode = ThemeMode(rawValue: themeModeRaw) {
            self.themeMode = mode
        } else {
            self.themeMode = .light
        }

        self.autoPlayAudio = defaults.object(forKey: Keys.autoPlayAudio) as? Bool ?? true
        self.showPronunciation = defaults.object(forKey: Keys.showPronunciation) as? Bool ?? true
        self.exampleDisplayCount = defaults.object(forKey: Keys.exampleDisplayCount) as? Int ?? 3
        self.currentVocabularyId = defaults.string(forKey: Keys.currentVocabularyId)

        // 加载测试模式设置，默认全部启用
        self.testMode1Enabled = defaults.object(forKey: Keys.testMode1Enabled) as? Bool ?? true
        self.testMode2Enabled = defaults.object(forKey: Keys.testMode2Enabled) as? Bool ?? true
        self.testMode3Enabled = defaults.object(forKey: Keys.testMode3Enabled) as? Bool ?? true
        self.testMode4Enabled = defaults.object(forKey: Keys.testMode4Enabled) as? Bool ?? true

        // 加载习题设置
        self.exerciseCount = defaults.object(forKey: Keys.exerciseCount) as? Int ?? 10
        self.exerciseInitialWeight = defaults.object(forKey: Keys.exerciseInitialWeight) as? Double ?? 100.0
        self.exerciseResetThreshold = defaults.object(forKey: Keys.exerciseResetThreshold) as? Double ?? 5.0

        // 确保至少有一个测试模式启用
        ensureAtLeastOneTestModeEnabled()
    }

    /// 获取当前启用的测试模式列表
    var enabledTestModes: [TestMode] {
        var modes: [TestMode] = []
        if testMode1Enabled { modes.append(.wordToMeaning) }
        if testMode2Enabled { modes.append(.meaningToWord) }
        if testMode3Enabled { modes.append(.audioToSpelling) }
        if testMode4Enabled { modes.append(.exampleToWord) }
        return modes
    }

    /// 确保至少有一个测试模式启用
    private func ensureAtLeastOneTestModeEnabled() {
        if !testMode1Enabled && !testMode2Enabled && !testMode3Enabled && !testMode4Enabled {
            // 如果所有都关闭了，强制启用第一个
            testMode1Enabled = true
        }
    }

    /// 重置所有设置为默认值
    func resetToDefaults() {
        dailyLearningCount = 20
        randomTestCount = 10
        masteryThreshold = 3
        errorStatsTopN = 10
        errorStatsPeriod = .all
        themeMode = .light
        autoPlayAudio = true
        showPronunciation = true
        exampleDisplayCount = 3
        testMode1Enabled = true
        testMode2Enabled = true
        testMode3Enabled = true
        testMode4Enabled = true
        exerciseCount = 10
        exerciseInitialWeight = 100.0
        exerciseResetThreshold = 5.0
    }
}
