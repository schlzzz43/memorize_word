//
//  VocabularyBookListView.swift
//  VocabMaster2
//
//  Created on 2026/02/18.
//

import SwiftUI
import SwiftData

struct VocabularyBookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [VocabularyBook]

    @State private var service: VocabularyBookService?
    @State private var isExportMode = false
    @State private var selectedBooksForExport: Set<PersistentIdentifier> = []

    @State private var showingCreateSheet = false
    @State private var newBookName = ""

    @State private var bookToDelete: VocabularyBook?
    @State private var showingDeleteConfirm = false

    @State private var bookToRename: VocabularyBook?
    @State private var showingRenameAlert = false
    @State private var renameText = ""

    @State private var showingExportShareSheet = false
    @State private var exportFileURL: URL?

    @State private var showingToast = false
    @State private var toastMessage = ""

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
            ZStack {
                List {
                    ForEach(sortedBooks) { book in
                        if isExportMode {
                            // 导出模式：显示checkbox
                            HStack {
                                Image(systemName: selectedBooksForExport.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedBooksForExport.contains(book.id) ? .blue : .gray)
                                    .font(.title3)

                                VocabularyBookRow(book: book)
                                    .contentShape(Rectangle())
                            }
                            .onTapGesture {
                                toggleSelection(book)
                            }
                        } else {
                            // 正常模式：可点击进入详情
                            NavigationLink(destination: VocabularyBookDetailView(book: book)) {
                                VocabularyBookRow(book: book)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    bookToDelete = book
                                    showingDeleteConfirm = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }

                                Button {
                                    bookToRename = book
                                    renameText = book.name
                                    showingRenameAlert = true
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if !book.isDefault {
                                    Button {
                                        setAsDefault(book)
                                    } label: {
                                        Label("设为默认", systemImage: "star.fill")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if sortedBooks.isEmpty {
                        ContentUnavailableView {
                            Label("暂无生词本", systemImage: "book.pages")
                        } description: {
                            Text("点击右上角 + 按钮创建生词本")
                        }
                    }
                }

                // 导出按钮（右下角）
                if !isExportMode && !sortedBooks.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                enterExportMode()
                            } label: {
                                Image(systemName: "square.and.arrow.up.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.white, .blue)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                            .padding(20)
                        }
                    }
                }
            }
            .navigationTitle("生词本")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isExportMode {
                        Button("取消") {
                            exitExportMode()
                        }
                    } else {
                        Button {
                            showingCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }

                if isExportMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("导出") {
                            exportSelectedBooks()
                        }
                        .disabled(selectedBooksForExport.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateBookSheet(onConfirm: { name in
                    createBook(name: name)
                    showingCreateSheet = false
                })
            }
            .alert("确定删除生词本吗？", isPresented: $showingDeleteConfirm) {
                Button("取消", role: .cancel) { }
                Button("确定删除", role: .destructive) {
                    if let book = bookToDelete {
                        deleteBook(book)
                    }
                }
            } message: {
                if let book = bookToDelete {
                    Text("此操作不可恢复\n\n将删除：\n• \(book.wordCount)个单词")
                }
            }
            .alert("重命名生词本", isPresented: $showingRenameAlert) {
                TextField("生词本名称", text: $renameText)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) {
                    renameText = ""
                }
                Button("确定") {
                    if let book = bookToRename {
                        renameBook(book, newName: renameText)
                    }
                    renameText = ""
                }
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("请输入新的生词本名称")
            }
            .sheet(isPresented: $showingExportShareSheet) {
                if let url = exportFileURL {
                    ShareSheet(items: [url])
                }
            }
            .overlay(alignment: .top) {
                if showingToast {
                    ToastView(message: toastMessage)
                        .padding(.top, 50)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                if service == nil {
                    service = VocabularyBookService(modelContext: modelContext)
                    service?.ensureDefaultBook()
                }
            }
        }
    }

    // MARK: - Actions

    private func createBook(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        service?.createBook(name: trimmedName)
        showToast("已创建生词本「\(trimmedName)」")
    }

    private func deleteBook(_ book: VocabularyBook) {
        service?.deleteBook(book)
        showToast("已删除生词本")
    }

    private func renameBook(_ book: VocabularyBook, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        service?.renameBook(book, to: trimmedName)
        showToast("已重命名为「\(trimmedName)」")
    }

    private func setAsDefault(_ book: VocabularyBook) {
        service?.setDefaultBook(book)
        showToast("已将「\(book.name)」设为默认生词本")
    }

    private func enterExportMode() {
        isExportMode = true
        selectedBooksForExport.removeAll()
    }

    private func exitExportMode() {
        isExportMode = false
        selectedBooksForExport.removeAll()
    }

    private func toggleSelection(_ book: VocabularyBook) {
        if selectedBooksForExport.contains(book.id) {
            selectedBooksForExport.remove(book.id)
        } else {
            selectedBooksForExport.insert(book.id)
        }
    }

    private func exportSelectedBooks() {
        let selectedBooks = sortedBooks.filter { selectedBooksForExport.contains($0.id) }
        guard !selectedBooks.isEmpty else { return }

        if selectedBooks.count == 1 {
            // 导出单个生词本为txt
            if let url = service?.exportBookToTxt(selectedBooks[0]) {
                exportFileURL = url
                showingExportShareSheet = true
            }
        } else {
            // 导出多个生词本为zip
            if let url = service?.exportBooksToZip(selectedBooks) {
                exportFileURL = url
                showingExportShareSheet = true
            }
        }

        exitExportMode()
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

// MARK: - 生词本行视图
struct VocabularyBookRow: View {
    let book: VocabularyBook

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(book.name)
                        .font(.headline)

                    if book.isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Text("\(book.wordCount)个单词")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - 创建生词本Sheet
struct CreateBookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bookName = ""
    let onConfirm: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("生词本名称", text: $bookName)
                        .autocorrectionDisabled()
                } header: {
                    Text("创建新生词本")
                }
            }
            .navigationTitle("新建生词本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        onConfirm(bookName)
                    }
                    .disabled(bookName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Toast视图
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

#Preview {
    VocabularyBookListView()
        .modelContainer(for: [VocabularyBook.self, VocabularyBookWord.self], inMemory: true)
}
