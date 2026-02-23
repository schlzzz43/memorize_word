//
//  VocabularyBookSelectorSheet.swift
//  VocabMaster2
//
//  Created on 2026/02/18.
//

import SwiftUI
import SwiftData

/// 生词本选择器Sheet
/// 用于在添加单词时选择目标生词本
struct VocabularyBookSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [VocabularyBook]

    let word: String
    let onSelect: (PersistentIdentifier) -> Void

    // 排序后的生词本列表（默认生词本置顶）
    private var sortedBooks: [VocabularyBook] {
        books.sorted { book1, book2 in
            if book1.isDefault { return true }
            if book2.isDefault { return false }
            return book1.createdAt > book2.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedBooks) { book in
                        Button {
                            onSelect(book.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(book.name)
                                            .font(.body)
                                            .foregroundColor(.primary)

                                        if book.isDefault {
                                            Image(systemName: "star.fill")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }

                                    Text("\(book.wordCount)个单词")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("将「\(word)」添加到...")
                }
            }
            .navigationTitle("选择生词本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if sortedBooks.isEmpty {
                    ContentUnavailableView {
                        Label("暂无生词本", systemImage: "book.pages")
                    } description: {
                        Text("请先在生词本页面创建")
                    }
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: VocabularyBook.self, VocabularyBookWord.self, configurations: config)

    let book1 = VocabularyBook(name: "默认生词本", isDefault: true)
    container.mainContext.insert(book1)

    let book2 = VocabularyBook(name: "英语单词", isDefault: false)
    container.mainContext.insert(book2)

    return VocabularyBookSelectorSheet(word: "example") { _ in }
        .modelContainer(container)
}
