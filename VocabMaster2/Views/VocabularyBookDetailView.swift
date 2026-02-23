//
//  VocabularyBookDetailView.swift
//  VocabMaster2
//
//  Created on 2026/02/18.
//

import SwiftUI
import SwiftData

struct VocabularyBookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let book: VocabularyBook

    @State private var service: VocabularyBookService?

    @State private var wordToDelete: VocabularyBookWord?
    @State private var showingDeleteConfirm = false

    @State private var wordToEdit: VocabularyBookWord?
    @State private var showingEditAlert = false
    @State private var editText = ""

    @State private var showingToast = false
    @State private var toastMessage = ""

    // 按添加时间倒序排列（最新的在上面）
    private var sortedWords: [VocabularyBookWord] {
        book.words.sorted { $0.addedAt > $1.addedAt }
    }

    var body: some View {
        List {
            ForEach(sortedWords) { word in
                HStack {
                    Text(word.word)
                        .font(.body)

                    Spacer()

                    Text(formatDate(word.addedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        wordToDelete = word
                        showingDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }

                    Button {
                        wordToEdit = word
                        editText = word.word
                        showingEditAlert = true
                    } label: {
                        Label("修改", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if sortedWords.isEmpty {
                ContentUnavailableView {
                    Label("暂无单词", systemImage: "text.book.closed")
                } description: {
                    Text("长按词库中的例句单词添加")
                }
            }
        }
        .alert("确定删除单词吗？", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("确定删除", role: .destructive) {
                if let word = wordToDelete {
                    deleteWord(word)
                }
            }
        } message: {
            if let word = wordToDelete {
                Text("将删除单词「\(word.word)」")
            }
        }
        .alert("修改单词", isPresented: $showingEditAlert) {
            TextField("单词", text: $editText)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) {
                editText = ""
            }
            Button("确定") {
                if let word = wordToEdit {
                    updateWord(word, newText: editText)
                }
                editText = ""
            }
            .disabled(editText.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("请输入新的单词")
        }
        .overlay(alignment: .top) {
            if showingToast {
                ToastView(message: toastMessage)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            if service == nil {
                service = VocabularyBookService(modelContext: modelContext)
            }
        }
    }

    // MARK: - Actions

    private func deleteWord(_ word: VocabularyBookWord) {
        service?.deleteWord(word)
        showToast("已删除单词")
    }

    private func updateWord(_ word: VocabularyBookWord, newText: String) {
        let trimmedText = newText.trimmingCharacters(in: .whitespaces)
        guard !trimmedText.isEmpty else { return }

        service?.updateWord(word, newText: trimmedText)
        showToast("已修改为「\(trimmedText)」")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation {
            showingToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showingToast = false
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: VocabularyBook.self, VocabularyBookWord.self, configurations: config)

    let book = VocabularyBook(name: "示例生词本", isDefault: true)
    container.mainContext.insert(book)

    let word1 = VocabularyBookWord(word: "apple")
    word1.vocabularyBook = book
    container.mainContext.insert(word1)

    let word2 = VocabularyBookWord(word: "banana")
    word2.vocabularyBook = book
    container.mainContext.insert(word2)

    return NavigationStack {
        VocabularyBookDetailView(book: book)
            .modelContainer(container)
    }
}
