//
//  StatisticsView.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import SwiftUI
import SwiftData

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vocabularies: [Vocabulary]
    @Query private var exerciseSets: [ExerciseSet]
    @StateObject private var settings = AppSettings.shared

    @State private var stats: LearningStats = LearningStats()
    @State private var exerciseStats: ExerciseStats = ExerciseStats()

    private var currentVocabulary: Vocabulary? {
        vocabularies.first { $0.isSelected } ?? vocabularies.first
    }

    /// 是否有习题
    private var hasExercises: Bool {
        !exerciseSets.isEmpty && exerciseSets.contains { !$0.exercises.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 学习天数
                    StatCard(
                        icon: "calendar",
                        title: "学习天数",
                        value: "\(stats.totalLearningDays)天",
                        color: .blue
                    )

                    // 最易错单词
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("最易错单词")
                                .font(.headline)
                            Spacer()
                            Text(settings.errorStatsPeriod.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if stats.topErrorWords.isEmpty {
                            Text("暂无错误记录")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(Array(stats.topErrorWords.enumerated()), id: \.element.id) { index, errorStat in
                                HStack {
                                    Text("\(index + 1).")
                                        .foregroundColor(.secondary)
                                        .frame(width: 32, alignment: .trailing)

                                    Text(errorStat.word.word)
                                        .fontWeight(.medium)

                                    Spacer()

                                    Text("\(errorStat.errorCount)次")
                                        .foregroundColor(.red)
                                }
                                .padding(.vertical, 4)

                                if index < stats.topErrorWords.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    // 当前词库进度
                    if let vocab = currentVocabulary {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "chart.pie.fill")
                                    .foregroundColor(.purple)
                                Text("当前词库进度")
                                    .font(.headline)
                            }

                            Text(vocab.name)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            LearningProgressChart(vocabulary: vocab)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    // 习题错误统计
                    if hasExercises {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundColor(.blue)
                                Text("习题错误类型统计")
                                    .font(.headline)
                                Spacer()
                                Text(settings.errorStatsPeriod.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if exerciseStats.categoryErrors.isEmpty {
                                Text("暂无错误记录")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                ForEach(exerciseStats.categoryErrors) { categoryStat in
                                    VStack(spacing: 8) {
                                        HStack {
                                            Text(categoryStat.category)
                                                .fontWeight(.medium)
                                            Spacer()
                                            Text("错误率: \(ExerciseStatisticsService.formatPercentage(categoryStat.errorRate))")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }

                                        // 错误率进度条
                                        GeometryReader { geometry in
                                            HStack(spacing: 0) {
                                                Rectangle()
                                                    .fill(Color.red.opacity(0.7))
                                                    .frame(width: geometry.size.width * categoryStat.errorRate)

                                                Rectangle()
                                                    .fill(Color.green.opacity(0.3))
                                                    .frame(width: geometry.size.width * (1 - categoryStat.errorRate))
                                            }
                                        }
                                        .frame(height: 8)
                                        .cornerRadius(4)

                                        HStack {
                                            Text("错误: \(categoryStat.errorCount)次")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("总计: \(categoryStat.totalCount)次")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)

                                    if categoryStat.id != exerciseStats.categoryErrors.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }

                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("学习统计")
            .onAppear {
                loadStatistics()
                loadExerciseStatistics()
            }
            .refreshable {
                loadStatistics()
                loadExerciseStatistics()
            }
        }
    }

    private func loadStatistics() {
        let service = StatisticsService(modelContext: modelContext)
        stats = service.getStatistics(for: currentVocabulary)
    }

    private func loadExerciseStatistics() {
        let service = ExerciseStatisticsService(modelContext: modelContext)
        exerciseStats = service.getStatistics()
    }
}

// MARK: - 统计卡片
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    StatisticsView()
        .modelContainer(for: [Vocabulary.self, Word.self, WordState.self, StudyRecord.self, ExerciseSet.self, Exercise.self, ExerciseRecord.self], inMemory: true)
}
