//
//  SettingsView.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vocabularies: [Vocabulary]
    @StateObject private var settings = AppSettings.shared

    @State private var showingResetConfirm = false
    @State private var resetScope: ResetScope = .all
    @State private var selectedVocabularyForReset: Vocabulary?

    @State private var showingExportShare = false
    @State private var exportFileURL: URL?
    @State private var showingImportPicker = false
    @State private var showingImportResult = false
    @State private var importResultMessage = ""
    @State private var isExporting = false
    @State private var isImporting = false

    enum ResetScope {
        case all
        case single(Vocabulary)
    }

    var body: some View {
        NavigationStack {
            Form {
                // 学习设置
                Section("学习设置") {
                    Stepper("每日学习数量: \(settings.dailyLearningCount)", value: $settings.dailyLearningCount, in: 5...100, step: 5)

                    Stepper("随机测试数量: \(settings.randomTestCount)", value: $settings.randomTestCount, in: 5...50, step: 5)

                    Stepper("已掌握阈值: \(settings.masteryThreshold)次", value: $settings.masteryThreshold, in: 1...10)
                }

                // 习题设置
                Section("习题设置") {
                    Stepper("每次习题数量: \(settings.exerciseCount)", value: $settings.exerciseCount, in: 5...50, step: 5)
                }

                // 统计设置
                Section("统计设置") {
                    Stepper("错误统计Top: \(settings.errorStatsTopN)", value: $settings.errorStatsTopN, in: 5...20)

                    Picker("错误统计周期", selection: $settings.errorStatsPeriod) {
                        ForEach(ErrorStatsPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                }

                // 测试模式设置
                Section {
                    Toggle("看单词,选意思", isOn: $settings.testMode1Enabled)
                    Toggle("看意思,选单词", isOn: $settings.testMode2Enabled)
                    Toggle("听音频,默单词", isOn: $settings.testMode3Enabled)
                    Toggle("看例句,填单词", isOn: $settings.testMode4Enabled)
                } header: {
                    Text("测试模式")
                } footer: {
                    Text("至少需要启用一种测试模式")
                }

                // 单词详细页设置
                Section("单词详细页") {
                    Toggle("自动播放音频", isOn: $settings.autoPlayAudio)

                    Toggle("显示音标", isOn: $settings.showPronunciation)

                    Stepper("例句显示数量: \(settings.exampleDisplayCount)", value: $settings.exampleDisplayCount, in: 1...5)
                }

                // 学习统计
                Section {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                            Text("学习统计")
                        }
                    }
                } header: {
                    Text("数据分析")
                }

                // 主题设置
                Section("主题") {
                    Picker("主题模式", selection: $settings.themeMode) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 学习记录
                Section {
                    Button {
                        exportStudyRecords()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("导出学习记录")
                            Spacer()
                            if isExporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isExporting)

                    Button {
                        showingImportPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("导入学习记录")
                            Spacer()
                            if isImporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImporting)
                } header: {
                    Text("学习记录管理")
                } footer: {
                    Text("导出和导入所有词库的学习记录（JSON格式）")
                }

                // 数据重置
                Section {
                    Button(role: .destructive) {
                        resetScope = .all
                        showingResetConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("重置所有词库数据")
                        }
                    }

                    ForEach(vocabularies) { vocabulary in
                        Button(role: .destructive) {
                            selectedVocabularyForReset = vocabulary
                            resetScope = .single(vocabulary)
                            showingResetConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("重置 \(vocabulary.name) 数据")
                            }
                        }
                    }
                } header: {
                    Text("数据重置")
                } footer: {
                    Text("重置将清除学习状态和记录,但不会删除音频文件")
                }

                // 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.1.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .alert("确定重置学习数据吗?", isPresented: $showingResetConfirm) {
                Button("取消", role: .cancel) { }
                Button("确定重置", role: .destructive) {
                    performReset()
                }
            } message: {
                Text("此操作不可恢复\n\n将重置:\n• 所有单词状态\n• 所有学习记录\n• 复习队列\n\n音频文件不会被删除")
            }
            .sheet(isPresented: $showingExportShare) {
                if let url = exportFileURL {
                    ShareSheet(items: [url])
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
            .alert("导入结果", isPresented: $showingImportResult) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(importResultMessage)
            }
        }
    }

    private func performReset() {
        let service = VocabularyService(modelContext: modelContext)

        switch resetScope {
        case .all:
            service.resetAllData()
        case .single(let vocabulary):
            service.resetVocabularyData(vocabulary)
        }
    }

    private func exportStudyRecords() {
        isExporting = true

        Task { @MainActor in
            do {
                let service = StudyRecordExportService(modelContext: modelContext)
                let fileURL = try service.exportAllRecords()

                exportFileURL = fileURL
                showingExportShare = true
                isExporting = false
            } catch {
                importResultMessage = "导出失败：\(error.localizedDescription)"
                showingImportResult = true
                isExporting = false
            }
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            isImporting = true

            Task { @MainActor in
                // 获取安全作用域文件访问权限
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let service = StudyRecordExportService(modelContext: modelContext)
                    let (records, states, skipped) = try service.importRecords(from: url)

                    var message = "导入完成！"
                    if records > 0 {
                        message += "\n✓ 学习记录：\(records) 条"
                    }
                    if states > 0 {
                        message += "\n✓ 单词状态：\(states) 个"
                    }
                    if skipped > 0 {
                        message += "\n⊘ 跳过：\(skipped) 条"
                    }

                    importResultMessage = message
                    showingImportResult = true
                    isImporting = false
                } catch {
                    importResultMessage = "导入失败：\(error.localizedDescription)"
                    showingImportResult = true
                    isImporting = false
                }
            }

        case .failure(let error):
            importResultMessage = "选择文件失败：\(error.localizedDescription)"
            showingImportResult = true
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Vocabulary.self, Word.self, WordState.self, StudyRecord.self], inMemory: true)
}
