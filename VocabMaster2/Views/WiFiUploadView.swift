//
//  WiFiUploadView.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import SwiftUI
import SwiftData

struct WiFiUploadView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uploadService = WiFiUploadService.shared

    @State private var importResult: ImportResult?
    @State private var showingResult = false
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 状态图标
                Image(systemName: uploadService.isRunning ? "wifi" : "wifi.slash")
                    .font(.system(size: 80))
                    .foregroundColor(uploadService.isRunning ? .green : .gray)
                    .padding(.top, 40)

                // 服务状态
                if uploadService.isRunning {
                    VStack(spacing: 12) {
                        Text("WiFi上传已开启")
                            .font(.headline)

                        Text("请在电脑浏览器中访问:")
                            .foregroundColor(.secondary)

                        Text(uploadService.serverAddress)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .textSelection(.enabled)

                        Text(uploadService.uploadStatus)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                } else {
                    VStack(spacing: 12) {
                        Text("WiFi上传未开启")
                            .font(.headline)

                        Text("开启后可通过电脑浏览器上传词库ZIP文件")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()

                // 说明
                VStack(alignment: .leading, spacing: 8) {
                    Text("使用说明:")
                        .font(.headline)

                    Text("1. 确保手机和电脑在同一WiFi网络")
                    Text("2. 点击下方按钮开启服务")
                    Text("3. 在电脑浏览器中打开显示的地址")
                    Text("4. 选择或拖拽ZIP文件上传")
                    Text("5. 上传完成后自动导入词库")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // 开启/关闭按钮
                Button {
                    if uploadService.isRunning {
                        uploadService.stop()
                    } else {
                        uploadService.start()
                    }
                } label: {
                    Text(uploadService.isRunning ? "关闭服务" : "开启服务")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(uploadService.isRunning ? Color.red : Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("WiFi上传")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        uploadService.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupUploadHandler()
            }
            .onDisappear {
                uploadService.stop()
            }
            .overlay {
                if isImporting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在导入...")
                            .font(.headline)
                    }
                    .padding(30)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                }
            }
            .alert("导入结果", isPresented: $showingResult) {
                Button("确定") {
                    if importResult?.successCount ?? 0 > 0 {
                        dismiss()
                    }
                }
            } message: {
                if let result = importResult {
                    Text(result.summary)
                }
            }
        }
    }

    private func setupUploadHandler() {
        uploadService.onVocabularyFileReceived = { [self] fileURL, originalFileName in
            Task { @MainActor in
                isImporting = true

                // 不传递词库名，让系统自动使用压缩包内txt文件的名字作为词库名
                let service = VocabularyService(modelContext: modelContext)
                let (_, result) = await service.importFromZip(zipURL: fileURL, vocabularyName: nil)

                isImporting = false
                importResult = result
                showingResult = true

                // 清理临时文件
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

#Preview {
    WiFiUploadView()
        .modelContainer(for: [Vocabulary.self, Word.self, WordState.self, StudyRecord.self], inMemory: true)
}
