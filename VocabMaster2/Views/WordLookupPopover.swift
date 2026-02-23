import SwiftUI

/// 单词查询弹窗 - 使用Google网页查询
/// 与WordDetailView中的查词逻辑一致
struct WordLookupPopover: View {
    let word: String
    let onDismiss: () -> Void

    var body: some View {
        if let url = createSearchURL() {
            SafariView(url: url)
                .ignoresSafeArea()
        } else {
            errorView
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("无法创建搜索链接")
                .font(.headline)

            Text("请检查网络连接后重试")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    /// 创建Google搜索URL（与WordDetailView一致）
    private func createSearchURL() -> URL? {
        let query = "\(word) 中文释义"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }
}

#Preview {
    WordLookupPopover(word: "example") {
        // Dismissed
    }
}
