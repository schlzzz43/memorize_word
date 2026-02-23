//
//  HomeView.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vocabularies: [Vocabulary]
    @Query private var exerciseSets: [ExerciseSet]

    @State private var showingNewLearning = false
    @State private var showingReview = false
    @State private var showingRandomTest = false
    @State private var showingNoVocabularyAlert = false
    @State private var exerciseStats: ExerciseStats = ExerciseStats()

    private var currentVocabulary: Vocabulary? {
        vocabularies.first { $0.isSelected } ?? vocabularies.first
    }

    /// 计算所有词库中已掌握单词的总数（用于随机测试）
    private var totalMasteredCount: Int {
        vocabularies.reduce(0) { $0 + $1.masteredCount }
    }

    /// 是否有习题
    private var hasExercises: Bool {
        !exerciseSets.isEmpty && exerciseSets.contains { !$0.exercises.isEmpty }
    }

    /// 今日学习统计
    private var todayStats: (newWords: Int, reviewWords: Int) {
        guard let vocab = currentVocabulary else { return (0, 0) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var newWordsCount = 0
        var reviewWordsCount = 0

        for word in vocab.words {
            for record in word.studyRecords {
                // 只统计今天的记录
                let recordDay = calendar.startOfDay(for: record.createdAt)
                if recordDay == today {
                    // 只统计测试通过的记录（result=true），表示状态发生了转变
                    // newLearning: unlearned → reviewing
                    // review: reviewing 状态保持或 → mastered
                    guard record.result else { continue }

                    switch record.type {
                    case .newLearning:
                        newWordsCount += 1
                    case .review:
                        reviewWordsCount += 1
                    case .randomTest:
                        break // 随机测试不计入统计
                    }
                }
            }
        }

        return (newWordsCount, reviewWordsCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 当前词库名称
                    if let vocab = currentVocabulary {
                        Text(vocab.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.top, 20)
                    } else {
                        Text("请先导入词库")
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .padding(.top, 20)
                    }

                    // 功能入口按钮
                    VStack(spacing: 16) {
                        StudyButton(
                            title: "学习新单词",
                            icon: "plus.circle.fill",
                            color: .blue,
                            subtitle: currentVocabulary.map { "未学习: \($0.unlearnedCount)个" }
                        ) {
                            if currentVocabulary != nil {
                                showingNewLearning = true
                            } else {
                                showingNoVocabularyAlert = true
                            }
                        }

                        StudyButton(
                            title: "复习旧单词",
                            icon: "arrow.clockwise.circle.fill",
                            color: .orange,
                            subtitle: currentVocabulary.map { "可复习: \($0.availableReviewingCount)个" }
                        ) {
                            if currentVocabulary != nil {
                                showingReview = true
                            } else {
                                showingNoVocabularyAlert = true
                            }
                        }

                        StudyButton(
                            title: "随机测试",
                            icon: "shuffle.circle.fill",
                            color: .purple,
                            subtitle: vocabularies.isEmpty ? nil : "可测试: \(totalMasteredCount)个 (已掌握)"
                        ) {
                            if currentVocabulary != nil {
                                showingRandomTest = true
                            } else {
                                showingNoVocabularyAlert = true
                            }
                        }
                    }
                    .padding(.horizontal)

                    // 今日学习统计
                    if currentVocabulary != nil {
                        TodayStudyStatsCard(
                            newWordsCount: todayStats.newWords,
                            reviewWordsCount: todayStats.reviewWords
                        )
                        .padding(.horizontal)
                    }

                    // 单词学习概况条状图
                    if let vocab = currentVocabulary {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("单词学习概况")
                                .font(.headline)
                                .padding(.horizontal)

                            LearningProgressChart(vocabulary: vocab)
                                .padding(.horizontal)
                        }
                        .padding(.top, 8)
                    }

                    // 习题学习概况
                    if hasExercises {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("习题学习概况")
                                .font(.headline)
                                .padding(.horizontal)

                            ExerciseProgressChart(overview: exerciseStats.overview)
                                .padding(.horizontal)
                        }
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 50)
                }
            }
            .navigationTitle("背单词")
            .navigationDestination(isPresented: $showingNewLearning) {
                if let vocab = currentVocabulary {
                    StudySessionView(vocabulary: vocab, mode: .newLearning)
                }
            }
            .navigationDestination(isPresented: $showingReview) {
                if let vocab = currentVocabulary {
                    StudySessionView(vocabulary: vocab, mode: .review)
                }
            }
            .navigationDestination(isPresented: $showingRandomTest) {
                if let vocab = currentVocabulary {
                    StudySessionView(vocabulary: vocab, mode: .randomTest)
                }
            }
            .alert("提示", isPresented: $showingNoVocabularyAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("请先在词库页面导入词库")
            }
            .onAppear {
                loadExerciseStatistics()
            }
            .refreshable {
                loadExerciseStatistics()
            }
        }
    }

    private func loadExerciseStatistics() {
        let service = ExerciseStatisticsService(modelContext: modelContext)
        exerciseStats = service.getStatistics()
    }
}

// MARK: - 学习按钮组件
struct StudyButton: View {
    let title: String
    let icon: String
    let color: Color
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
}

// MARK: - 学习进度条状图
struct LearningProgressChart: View {
    let vocabulary: Vocabulary

    private var total: Int {
        vocabulary.totalCount
    }

    var body: some View {
        VStack(spacing: 16) {
            // 状态标签
            HStack(spacing: 20) {
                StatusLabel(
                    title: "未学习",
                    count: vocabulary.unlearnedCount,
                    color: .gray
                )
                StatusLabel(
                    title: "待复习",
                    count: vocabulary.reviewingCount,
                    color: .orange
                )
                StatusLabel(
                    title: "已掌握",
                    count: vocabulary.masteredCount,
                    color: .green
                )
            }

            // 进度条
            if total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: geometry.size.width * CGFloat(vocabulary.unlearnedCount) / CGFloat(total))

                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: geometry.size.width * CGFloat(vocabulary.reviewingCount) / CGFloat(total))

                        Rectangle()
                            .fill(Color.green)
                            .frame(width: geometry.size.width * CGFloat(vocabulary.masteredCount) / CGFloat(total))
                    }
                    .cornerRadius(4)
                }
                .frame(height: 12)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct StatusLabel: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text("\(count)")
                .font(.title3)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 习题学习进度概况
struct ExerciseProgressChart: View {
    let overview: ExerciseOverview

    var body: some View {
        VStack(spacing: 16) {
            // 统计指标
            HStack(spacing: 20) {
                StatItem(
                    title: "总题数",
                    value: "\(overview.totalExercises)",
                    color: .blue
                )
                StatItem(
                    title: "已练习",
                    value: "\(overview.attemptedExercises)",
                    color: .orange
                )
                StatItem(
                    title: "正确率",
                    value: ExerciseStatisticsService.formatPercentage(overview.correctRate),
                    color: .green
                )
            }

            // 进度条
            if overview.totalExercises > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        // 未练习部分
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: geometry.size.width * CGFloat(overview.totalExercises - overview.attemptedExercises) / CGFloat(overview.totalExercises))

                        // 已练习部分
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * CGFloat(overview.attemptedExercises) / CGFloat(overview.totalExercises))
                    }
                    .cornerRadius(4)
                }
                .frame(height: 12)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - 今日学习统计卡片
struct TodayStudyStatsCard: View {
    let newWordsCount: Int
    let reviewWordsCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .font(.headline)
                    .foregroundColor(.blue)
                Text("今日学习情况")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 32) {
                TodayStatItem(
                    title: "新学单词",
                    count: newWordsCount,
                    icon: "plus.circle.fill",
                    color: .blue
                )

                TodayStatItem(
                    title: "复习单词",
                    count: reviewWordsCount,
                    icon: "arrow.clockwise.circle.fill",
                    color: .orange
                )

                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct TodayStatItem: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Vocabulary.self, Word.self, WordState.self, StudyRecord.self, ExerciseSet.self, Exercise.self, ExerciseRecord.self], inMemory: true)
}
