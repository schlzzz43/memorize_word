import SwiftUI
import SwiftData

struct ExerciseSetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AppSettings.shared
    let exerciseSet: ExerciseSet

    @State private var showExerciseSession = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 统计卡片
                statisticsSection

                // 开始答题按钮
                if eligibleCount > 0 {
                    Button {
                        showExerciseSession = true
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("开始答题 (\(settings.exerciseCount)题)")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                } else {
                    noEligibleExercisesView
                }

                Spacer(minLength: 20)
            }
            .padding(.top)
        }
        .navigationTitle(exerciseSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showExerciseSession) {
            ExerciseSessionView(exerciseSet: exerciseSet)
        }
    }

    private var statisticsSection: some View {
        VStack(spacing: 16) {
            ExerciseStatCard(
                icon: "doc.text.fill",
                title: "总习题数",
                value: "\(totalCount)",
                color: .blue
            )

            ExerciseStatCard(
                icon: "checkmark.circle.fill",
                title: "可答习题数",
                value: "\(eligibleCount)",
                color: .green
            )

            ExerciseStatCard(
                icon: "chart.bar.fill",
                title: "完成率",
                value: String(format: "%.1f%%", completionRate),
                color: .orange
            )

            if totalAnsweredCount > 0 {
                ExerciseStatCard(
                    icon: "target",
                    title: "正确率",
                    value: String(format: "%.1f%%", correctRate),
                    color: .purple
                )
            }
        }
        .padding(.horizontal)
    }

    private var noEligibleExercisesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("暂无可答习题")
                .font(.headline)

            Text("习题的单词必须是\"待复习\"或\"已掌握\"状态")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Computed Properties

    private var totalCount: Int {
        exerciseSet.exercises.count
    }

    private var eligibleCount: Int {
        exerciseSet.exercises.filter { exercise in
            guard let word = exercise.word,
                  let status = word.state?.status else {
                return false
            }
            return status == .reviewing || status == .mastered
        }.count
    }

    private var completionRate: Double {
        guard totalCount > 0 else { return 0 }
        let completed = exerciseSet.exercises.filter { !$0.records.isEmpty }.count
        return Double(completed) / Double(totalCount) * 100
    }

    private var totalAnsweredCount: Int {
        exerciseSet.exercises.reduce(0) { $0 + $1.records.count }
    }

    private var correctCount: Int {
        exerciseSet.exercises.reduce(0) { total, exercise in
            total + exercise.records.filter { $0.isCorrect }.count
        }
    }

    private var correctRate: Double {
        guard totalAnsweredCount > 0 else { return 0 }
        return Double(correctCount) / Double(totalAnsweredCount) * 100
    }
}

private struct ExerciseStatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
