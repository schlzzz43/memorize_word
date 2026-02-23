import SwiftUI
import SwiftData

struct ExerciseWiFiUploadView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uploadService = WiFiUploadService.shared

    @State private var importResult: ExerciseImportResult?
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

                        Text("开启后可通过电脑浏览器上传习题ZIP文件")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()

                // 说明
                VStack(alignment: .leading, spacing: 8) {
                    Text("文件格式要求:")
                        .font(.headline)

                    Text("• 文件类型：.txt文本文件")
                    Text("• 文件编码：UTF-8")
                    Text("• 每行9个字段，用|分隔:")
                        .fontWeight(.semibold)
                    Text("  Word|Question|A|B|C|D|Answer|Explanation|Category")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Text("\n示例:")
                        .fontWeight(.semibold)
                        .padding(.top, 4)
                    Text("final|Ms. Chen requested...|final|finally|finalize|finality|A|空格修饰名词...|词性辨析")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            .navigationTitle("WiFi上传习题")
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
                        Text("正在导入习题...")
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
                    Text(resultSummary(result))
                }
            }
        }
    }

    private func setupUploadHandler() {
        uploadService.onExerciseFileReceived = { fileURL, originalFileName in
            Task { @MainActor in
                isImporting = true

                let importService = ExerciseImportService(modelContext: modelContext)
                let result = await importService.importFromTxt(txtURL: fileURL, fileName: originalFileName)

                isImporting = false
                importResult = result
                showingResult = true

                // 删除临时文件
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func resultSummary(_ result: ExerciseImportResult) -> String {
        var summary = ""

        if !result.exerciseSetName.isEmpty {
            summary += "习题集: \(result.exerciseSetName)\n\n"
        }

        summary += "✅ 成功导入: \(result.successCount)题\n"

        if result.failedCount > 0 {
            summary += "❌ 导入失败: \(result.failedCount)题\n"
        }

        if result.skippedCount > 0 {
            summary += "⚠️ 跳过(单词未导入): \(result.skippedCount)题\n"
        }

        if !result.errorMessages.isEmpty {
            summary += "\n错误详情:\n"
            for (index, message) in result.errorMessages.prefix(5).enumerated() {
                summary += "\(index + 1). \(message)\n"
            }
            if result.errorMessages.count > 5 {
                summary += "...还有\(result.errorMessages.count - 5)个错误"
            }
        }

        return summary
    }
}
