import Foundation

/// 单词查询结果
struct WordLookupResult {
    var phoneticUS: String?        // 美式音标
    var phoneticUK: String?        // 英式音标
    var meanings: [Meaning]        // 释义列表
    var example: String?           // 第一个例句

    struct Meaning {
        var partOfSpeech: String   // 词性 (n., v., adj., etc.)
        var definition: String     // 释义
    }
}

@MainActor
class WordLookupService {

    enum LookupError: Error, LocalizedError {
        case invalidURL
        case networkError(Error)
        case parseError
        case timeout

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "无效的URL"
            case .networkError(let error):
                return "网络错误: \(error.localizedDescription)"
            case .parseError:
                return "解析失败"
            case .timeout:
                return "请求超时"
            }
        }
    }

    /// 查询单词释义（从有道网页）
    func lookup(word: String) async throws -> WordLookupResult {
        // 构造URL
        let urlString = "https://www.youdao.com/result?word=\(word)&lang=en"
        guard let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedURL) else {
            throw LookupError.invalidURL
        }

        // 设置请求（添加User-Agent避免反爬虫）
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        // 发起请求
        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw LookupError.networkError(error)
        }

        // 解析HTML
        guard let html = String(data: data, encoding: .utf8) else {
            throw LookupError.parseError
        }

        return try parseYoudaoHTML(html, word: word)
    }

    /// 解析有道HTML（简化版regex解析）
    private func parseYoudaoHTML(_ html: String, word: String) throws -> WordLookupResult {
        var result = WordLookupResult(meanings: [])

        // 解析美式音标
        // 匹配模式: 美 [ˈæpl] 或 美: /ˈæpl/
        if let usRange = html.range(of: #"美\s*[\[/]([^\]/]+)[\]/]"#, options: .regularExpression) {
            let matched = String(html[usRange])
            if let phonetic = extractPhonetic(from: matched) {
                result.phoneticUS = "/\(phonetic)/"
            }
        }

        // 解析英式音标
        // 匹配模式: 英 [ˈæpl] 或 英: /ˈæpl/
        if let ukRange = html.range(of: #"英\s*[\[/]([^\]/]+)[\]/]"#, options: .regularExpression) {
            let matched = String(html[ukRange])
            if let phonetic = extractPhonetic(from: matched) {
                result.phoneticUK = "/\(phonetic)/"
            }
        }

        // 解析释义
        // 有道的释义通常在 <li> 或特定的 div 中，格式如: n. 苹果; v. 使用
        let meaningPatterns = [
            #"<li[^>]*>([^<]*(?:n\.|v\.|adj\.|adv\.|prep\.|conj\.|pron\.|num\.|int\.)[^<]*)</li>"#,
            #"<div[^>]*class="[^"]*trans"[^>]*>([^<]*(?:n\.|v\.|adj\.|adv\.)[^<]*)</div>"#,
            #"<p[^>]*>([^<]*(?:n\.|v\.|adj\.|adv\.)[^<]*)</p>"#
        ]

        var foundMeanings: [WordLookupResult.Meaning] = []

        for pattern in meaningPatterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let nsString = html as NSString
            let matches = regex?.matches(in: html, range: NSRange(location: 0, length: nsString.length)) ?? []

            for match in matches.prefix(3) {  // 最多3个释义
                if match.numberOfRanges >= 2 {
                    let range = match.range(at: 1)
                    let meaningText = nsString.substring(with: range)
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if let parsed = parseMeaning(meaningText) {
                        foundMeanings.append(parsed)
                    }
                }
            }

            if !foundMeanings.isEmpty {
                break  // 找到释义后停止
            }
        }

        result.meanings = Array(foundMeanings.prefix(3))

        // 解析例句
        // 匹配例句模式
        let examplePatterns = [
            #"<p[^>]*class="[^"]*example[^"]*"[^>]*>([^<]+)</p>"#,
            #"<div[^>]*class="[^"]*example[^"]*"[^>]*>([^<]+)</div>"#,
            #"<li[^>]*class="[^"]*sent[^"]*"[^>]*>([^<]+)</li>"#
        ]

        for pattern in examplePatterns {
            if let exampleRange = html.range(of: pattern, options: .regularExpression) {
                let matched = String(html[exampleRange])
                let cleaned = matched
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !cleaned.isEmpty && cleaned.count > 5 {
                    result.example = cleaned
                    break
                }
            }
        }

        // 如果没有找到任何有效数据，抛出解析错误
        if result.phoneticUS == nil && result.phoneticUK == nil && result.meanings.isEmpty {
            throw LookupError.parseError
        }

        return result
    }

    /// 从文本中提取音标
    private func extractPhonetic(from text: String) -> String? {
        let pattern = #"[\[/]([^\]/]+)[\]/]"#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        let matched = String(text[range])
        return matched
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "/", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 解析释义文本（如: "n. 苹果; 苹果公司"）
    private func parseMeaning(_ text: String) -> WordLookupResult.Meaning? {
        // 查找词性标记
        let posPatterns = ["n\\.", "v\\.", "adj\\.", "adv\\.", "prep\\.", "conj\\.", "pron\\.", "num\\.", "int\\."]

        for posPattern in posPatterns {
            if let range = text.range(of: posPattern, options: .regularExpression) {
                let pos = String(text[range])
                let definition = text
                    .replacingOccurrences(of: posPattern, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ";,"))

                if !definition.isEmpty {
                    return WordLookupResult.Meaning(
                        partOfSpeech: pos,
                        definition: definition
                    )
                }
            }
        }

        return nil
    }
}
