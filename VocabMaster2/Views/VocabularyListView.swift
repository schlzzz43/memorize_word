//
//  VocabularyListView.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import SwiftUI
import SwiftData

struct VocabularyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vocabulary.createdAt, order: .reverse) private var vocabularies: [Vocabulary]

    @State private var showingWiFiUpload = false
    @State private var vocabularyToDelete: Vocabulary?
    @State private var showingDeleteConfirm = false
    @State private var vocabularyToRename: Vocabulary?
    @State private var showingRenameAlert = false
    @State private var newVocabularyName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(vocabularies) { vocabulary in
                    NavigationLink(destination: WordListView(vocabulary: vocabulary)) {
                        VocabularyRow(vocabulary: vocabulary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            vocabularyToDelete = vocabulary
                            showingDeleteConfirm = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }

                        Button {
                            vocabularyToRename = vocabulary
                            newVocabularyName = vocabulary.name
                            showingRenameAlert = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            let service = VocabularyService(modelContext: modelContext)
                            service.setCurrentVocabulary(vocabulary)
                        } label: {
                            Label("选为当前", systemImage: "checkmark.circle")
                        }
                        .tint(.blue)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("词库")
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showingWiFiUpload = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white, .blue)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .padding(20)
            }
            .sheet(isPresented: $showingWiFiUpload) {
                WiFiUploadView()
            }
            .alert("确定删除词库吗？", isPresented: $showingDeleteConfirm) {
                Button("取消", role: .cancel) { }
                Button("确定删除", role: .destructive) {
                    if let vocab = vocabularyToDelete {
                        deleteVocabulary(vocab)
                    }
                }
            } message: {
                if let vocab = vocabularyToDelete {
                    Text("此操作不可恢复\n\n将删除：\n• \(vocab.totalCount)个单词\n• 所有学习记录\n• 所有音频文件")
                }
            }
            .alert("重命名词库", isPresented: $showingRenameAlert) {
                TextField("词库名称", text: $newVocabularyName)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) {
                    newVocabularyName = ""
                }
                Button("确定") {
                    if let vocab = vocabularyToRename {
                        renameVocabulary(vocab, newName: newVocabularyName)
                    }
                    newVocabularyName = ""
                }
                .disabled(newVocabularyName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("请输入新的词库名称")
            }
            .overlay {
                if vocabularies.isEmpty {
                    ContentUnavailableView {
                        Label("暂无词库", systemImage: "books.vertical")
                    } description: {
                        Text("点击右下角 ⊕ 按钮通过WiFi导入词库")
                    }
                }
            }
        }
    }

    private func deleteVocabulary(_ vocabulary: Vocabulary) {
        let service = VocabularyService(modelContext: modelContext)
        service.deleteVocabulary(vocabulary)
    }

    private func renameVocabulary(_ vocabulary: Vocabulary, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // 检查是否与其他词库重名
        let existingVocab = vocabularies.first { $0.name == trimmedName && $0.id != vocabulary.id }
        if existingVocab != nil {
            return
        }

        // 重命名音频文件夹
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldAudioPath = documentsPath.appendingPathComponent("Audio/\(vocabulary.name)")
        let newAudioPath = documentsPath.appendingPathComponent("Audio/\(trimmedName)")

        if FileManager.default.fileExists(atPath: oldAudioPath.path) {
            try? FileManager.default.moveItem(at: oldAudioPath, to: newAudioPath)
        }

        // 更新词库名称和单词的音频路径
        let oldName = vocabulary.name
        vocabulary.name = trimmedName

        for word in vocabulary.words {
            if let audioPath = word.audioPath {
                word.audioPath = audioPath.replacingOccurrences(of: "Audio/\(oldName)/", with: "Audio/\(trimmedName)/")
            }

            for (index, example) in word.examples.enumerated() {
                if let exampleAudio = example.audio {
                    var updatedExamples = word.examples
                    updatedExamples[index].audio = exampleAudio.replacingOccurrences(of: "Audio/\(oldName)/", with: "Audio/\(trimmedName)/")
                    word.examples = updatedExamples
                }
            }
        }

        try? modelContext.save()
    }
}

// MARK: - 词库行视图
struct VocabularyRow: View {
    let vocabulary: Vocabulary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(vocabulary.name)
                        .font(.headline)

                    Text("(\(vocabulary.totalCount)词)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Label("\(vocabulary.unlearnedCount)", systemImage: "sparkle")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Label("\(vocabulary.availableReviewingCount)", systemImage: "arrow.clockwise.circle")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Label("\(vocabulary.masteredCount)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            // 选中状态指示器（只显示，不可点击）
            if vocabulary.isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
        }
    }
}

#Preview {
    VocabularyListView()
        .modelContainer(for: [Vocabulary.self, Word.self, WordState.self, StudyRecord.self], inMemory: true)
}
