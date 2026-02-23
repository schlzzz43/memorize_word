import SwiftUI
import SwiftData

struct ExerciseSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var exerciseService: ExerciseService?

    let exerciseSet: ExerciseSet

    @State private var selectedAnswer: String? = nil
    @State private var showResult = false
    @State private var isCorrect = false

    // 查词功能状态
    @State private var selectedWord: String?
    @State private var showLookup = false

    var body: some View {
        NavigationStack {
            Group {
                if let service = exerciseService {
                    if service.isCompleted {
                        CompletionView {
                            dismiss()
                        }
                    } else if let exercise = service.currentExercise {
                        answerView(for: exercise)
                    } else {
                        ProgressView("加载中...")
                    }
                } else {
                    ProgressView("初始化中...")
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("退出") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // 初始化service with proper context
            let service = ExerciseService(modelContext: modelContext)
            service.startExerciseSession(for: exerciseSet)
            exerciseService = service
        }
    }

    private func answerView(for exercise: Exercise) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // 进度条
                if let service = exerciseService {
                    VStack(spacing: 8) {
                        ProgressView(value: service.progress)
                            .tint(.blue)

                        Text("第 \(service.currentIndex + 1) / \(service.currentExercises.count) 题")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }

                // 题目
                VStack(alignment: .leading, spacing: 12) {
                    SelectableTextView(
                        text: exercise.question,
                        font: .preferredFont(forTextStyle: .body),
                        textColor: .label,
                        backgroundColor: .clear
                    ) { word in
                        selectedWord = word
                        showLookup = true
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    Text("💡 长按题目、选项或解析中的单词可查询释义")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // 选项
                VStack(spacing: 12) {
                    OptionButton(
                        letter: "A",
                        text: exercise.optionA,
                        isSelected: selectedAnswer == "A",
                        isCorrect: showResult && exercise.correctAnswer == "A",
                        showResult: showResult
                    ) {
                        selectAnswer("A")
                    }

                    OptionButton(
                        letter: "B",
                        text: exercise.optionB,
                        isSelected: selectedAnswer == "B",
                        isCorrect: showResult && exercise.correctAnswer == "B",
                        showResult: showResult
                    ) {
                        selectAnswer("B")
                    }

                    OptionButton(
                        letter: "C",
                        text: exercise.optionC,
                        isSelected: selectedAnswer == "C",
                        isCorrect: showResult && exercise.correctAnswer == "C",
                        showResult: showResult
                    ) {
                        selectAnswer("C")
                    }

                    OptionButton(
                        letter: "D",
                        text: exercise.optionD,
                        isSelected: selectedAnswer == "D",
                        isCorrect: showResult && exercise.correctAnswer == "D",
                        showResult: showResult
                    ) {
                        selectAnswer("D")
                    }
                }
                .padding(.horizontal)

                // 结果和解析
                if showResult {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(isCorrect ? .green : .red)
                            Text(isCorrect ? "回答正确！" : "回答错误")
                                .font(.headline)
                                .foregroundColor(isCorrect ? .green : .red)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("解析:")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            SelectableTextView(
                                text: exercise.explanation,
                                font: .preferredFont(forTextStyle: .body),
                                textColor: .label,
                                backgroundColor: .clear
                            ) { word in
                                selectedWord = word
                                showLookup = true
                            }

                            HStack {
                                Text("题型:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(exercise.testCategory)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // 提交/下一题按钮
                Button {
                    if showResult {
                        nextExercise()
                    } else {
                        submitAnswer()
                    }
                } label: {
                    Text(showResult ? "下一题 →" : "提交答案")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedAnswer != nil || showResult ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(selectedAnswer == nil && !showResult)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding(.top)
        }
        .sheet(isPresented: $showLookup) {
            if let word = selectedWord {
                WordLookupPopover(word: word) {
                    showLookup = false
                }
            }
        }
    }

    private func selectAnswer(_ answer: String) {
        guard !showResult else { return }
        selectedAnswer = answer
    }

    private func submitAnswer() {
        guard let answer = selectedAnswer,
              let service = exerciseService,
              let exercise = service.currentExercise else { return }

        isCorrect = service.processAnswer(answer, for: exercise)
        showResult = true
    }

    private func nextExercise() {
        exerciseService?.moveToNext()
        selectedAnswer = nil
        showResult = false
        isCorrect = false
    }
}

struct OptionButton: View {
    let letter: String
    let text: String
    let isSelected: Bool
    let isCorrect: Bool
    let showResult: Bool
    let action: () -> Void

    // 查词功能状态
    @State private var selectedWord: String?
    @State private var showLookup = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(letter)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(circleColor)
                    .clipShape(Circle())

                SelectableTextView(
                    text: text,
                    font: .preferredFont(forTextStyle: .body),
                    textColor: .label,
                    backgroundColor: .clear
                ) { word in
                    selectedWord = word
                    showLookup = true
                }
                .allowsHitTesting(showResult)  // 只在显示结果后启用查词
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .disabled(showResult)
        .sheet(isPresented: $showLookup) {
            if let word = selectedWord {
                WordLookupPopover(word: word) {
                    showLookup = false
                }
            }
        }
    }

    private var circleColor: Color {
        if showResult && isCorrect {
            return .green
        } else if isSelected {
            return .blue
        } else {
            return .gray
        }
    }

    private var backgroundColor: Color {
        if showResult && isCorrect {
            return Color.green.opacity(0.1)
        } else if showResult && isSelected && !isCorrect {
            return Color.red.opacity(0.1)
        } else if isSelected {
            return Color.blue.opacity(0.1)
        } else {
            return Color(.secondarySystemBackground)
        }
    }

    private var borderColor: Color {
        if showResult && isCorrect {
            return .green
        } else if showResult && isSelected && !isCorrect {
            return .red
        } else if isSelected {
            return .blue
        } else {
            return Color(.systemGray4)
        }
    }
}

struct CompletionView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("答题完成！")
                .font(.title)
                .fontWeight(.bold)

            Text("继续保持，加油！")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                onDismiss()
            } label: {
                Text("返回")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
    }
}
