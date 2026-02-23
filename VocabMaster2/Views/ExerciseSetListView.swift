import SwiftUI
import SwiftData

struct ExerciseSetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseSet.createdAt, order: .reverse) private var exerciseSets: [ExerciseSet]
    @State private var showWiFiUpload = false
    @State private var showDeleteConfirm = false
    @State private var setToDelete: ExerciseSet?

    var body: some View {
        NavigationStack {
            Group {
                if exerciseSets.isEmpty {
                    emptyStateView
                } else {
                    exerciseSetListView
                }
            }
            .navigationTitle("习题")
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showWiFiUpload = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white, .blue)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .padding(20)
            }
            .sheet(isPresented: $showWiFiUpload) {
                ExerciseWiFiUploadView()
            }
            .alert("确认删除", isPresented: $showDeleteConfirm, presenting: setToDelete) { set in
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    deleteExerciseSet(set)
                }
            } message: { set in
                Text("确定要删除习题集「\(set.name)」吗？\n这将删除所有习题和答题记录。")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("暂无习题集")
                .font(.title3)
                .fontWeight(.medium)

            Text("点击右下角 ⊕ 按钮上传习题文件")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exerciseSetListView: some View {
        List {
            ForEach(exerciseSets) { exerciseSet in
                NavigationLink(destination: ExerciseSetDetailView(exerciseSet: exerciseSet)) {
                    ExerciseSetRow(exerciseSet: exerciseSet)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        setToDelete = exerciseSet
                        showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func deleteExerciseSet(_ exerciseSet: ExerciseSet) {
        modelContext.delete(exerciseSet)
        try? modelContext.save()
    }
}

struct ExerciseSetRow: View {
    let exerciseSet: ExerciseSet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                Text(exerciseSet.name)
                    .font(.headline)
            }

            HStack(spacing: 16) {
                Label("\(exerciseSet.exercises.count)题", systemImage: "number")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("完成率 \(completionRate, specifier: "%.1f")%", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if eligibleCount > 0 {
                    Label("可答 \(eligibleCount)", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var completionRate: Double {
        let total = exerciseSet.exercises.count
        guard total > 0 else { return 0 }
        let completed = exerciseSet.exercises.filter { !$0.records.isEmpty }.count
        return Double(completed) / Double(total) * 100
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
}

#Preview {
    ExerciseSetListView()
        .modelContainer(for: [ExerciseSet.self, Exercise.self], inMemory: true)
}
