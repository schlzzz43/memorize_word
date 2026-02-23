//
//  WordListView.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import SwiftUI
import SwiftData

enum WordFilter: String, CaseIterable {
    case all = "全部"
    case unlearned = "未学习"
    case reviewing = "待复习"
    case mastered = "已掌握"
}

struct WordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var vocabulary: Vocabulary

    @State private var selectedFilter: WordFilter = .all
    @State private var wordToDelete: Word?
    @State private var showingDeleteConfirm = false
    @State private var displayLimit = 50
    @State private var searchText = ""

    init(vocabulary: Vocabulary) {
        self.vocabulary = vocabulary
    }

    private var filteredWords: [Word] {
        var words: [Word]
        switch selectedFilter {
        case .all:
            words = vocabulary.words
        case .unlearned:
            words = vocabulary.words.filter { $0.state?.status == .unlearned }
        case .reviewing:
            words = vocabulary.words.filter { $0.state?.status == .reviewing }
        case .mastered:
            words = vocabulary.words.filter { $0.state?.status == .mastered }
        }

        // 应用搜索过滤
        if !searchText.isEmpty {
            words = words.filter { word in
                word.word.localizedCaseInsensitiveContains(searchText) ||
                word.meaning.localizedCaseInsensitiveContains(searchText)
            }
        }

        return words.sorted { $0.word.lowercased() < $1.word.lowercased() }
    }

    private var displayedWords: [Word] {
        Array(filteredWords.prefix(displayLimit))
    }

    private var deleteAlertTitle: String {
        "确定删除\"\(wordToDelete?.word ?? "")\"吗？"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("搜索单词或释义", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 分组标签
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WordFilter.allCases, id: \.self) { filter in
                        FilterTag(
                            title: filter.rawValue,
                            count: countForFilter(filter),
                            isSelected: selectedFilter == filter
                        ) {
                            withAnimation {
                                selectedFilter = filter
                                displayLimit = 50
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(.systemBackground))

            // 单词列表
            List {
                ForEach(displayedWords) { word in
                    NavigationLink {
                        WordDetailView(word: word, isEditable: true)
                    } label: {
                        WordRow(word: word)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            wordToDelete = word
                            showingDeleteConfirm = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }

                // 加载更多
                if displayedWords.count < filteredWords.count {
                    Button {
                        displayLimit += 50
                    } label: {
                        HStack {
                            Spacer()
                            Text("加载更多...")
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("\(vocabulary.name) (\(filteredWords.count)词)")
        .navigationBarTitleDisplayMode(.inline)
        .alert(deleteAlertTitle, isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("确定删除", role: .destructive) {
                if let word = wordToDelete {
                    deleteWord(word)
                }
            }
        } message: {
            Text("此操作不可恢复\n\n将删除：\n• 单词数据\n• 学习记录\n• 相关音频文件")
        }
    }

    private func countForFilter(_ filter: WordFilter) -> Int {
        switch filter {
        case .all:
            return vocabulary.totalCount
        case .unlearned:
            return vocabulary.unlearnedCount
        case .reviewing:
            return vocabulary.reviewingCount
        case .mastered:
            return vocabulary.masteredCount
        }
    }

    private func deleteWord(_ word: Word) {
        let service = VocabularyService(modelContext: modelContext)
        service.deleteWord(word)
    }
}

// MARK: - 过滤标签
struct FilterTag: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("(\(count))")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

// MARK: - 单词行
struct WordRow: View {
    let word: Word

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.word)
                    .font(.headline)

                Text(word.meaning)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 状态图标
            statusIcon
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch word.state?.status {
        case .mastered:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .reviewing:
            Image(systemName: "arrow.clockwise.circle")
                .foregroundColor(.orange)
        case .unlearned, .none:
            Image(systemName: "sparkle")
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    NavigationStack {
        WordListView(vocabulary: Vocabulary(name: "测试词库"))
    }
    .modelContainer(for: [Vocabulary.self, Word.self, WordState.self, StudyRecord.self], inMemory: true)
}
