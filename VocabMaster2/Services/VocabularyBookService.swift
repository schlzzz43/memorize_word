//
//  VocabularyBookService.swift
//  VocabMaster2
//
//  Created on 2026/02/18.
//

import Foundation
import SwiftData

/// 生词本服务类
///
/// 负责生词本和生词本单词的完整生命周期管理。主要功能包括：
/// - 生词本的CRUD操作（创建、读取、更新、删除）
/// - 默认生词本的管理和自动初始化
/// - 单词的添加、删除和修改（带重复检测）
/// - 导出生词本为txt文件或zip压缩包
///
/// **架构设计：**
/// - 作为MVVM模式中的Service层
/// - @MainActor保证所有操作在主线程执行，确保UI更新线程安全
///
/// **默认生词本保证机制：**
/// - App启动时自动检查并创建默认生词本
/// - 删除生词本后自动维护默认生词本
/// - 确保系统中始终有一个默认生词本
@MainActor
class VocabularyBookService {

    // MARK: - 依赖项

    /// SwiftData上下文，用于数据库操作
    private var modelContext: ModelContext

    // MARK: - 常量

    /// 默认生词本名称
    private let defaultBookName = "默认生词本"

    // MARK: - 初始化

    /// 初始化生词本服务
    ///
    /// - Parameter modelContext: SwiftData上下文，用于数据库读写操作
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 生词本查询

    /// 获取所有生词本列表
    ///
    /// - Returns: 所有生词本数组，默认生词本置顶，其他按创建时间倒序排列
    ///
    /// **排序规则：**
    /// 1. 默认生词本（isDefault=true）排在最前面
    /// 2. 其他生词本按createdAt降序排列
    func getAllBooks() -> [VocabularyBook] {
        let descriptor = FetchDescriptor<VocabularyBook>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let books = try? modelContext.fetch(descriptor) else {
            return []
        }

        // 将默认生词本置顶
        return books.sorted { book1, book2 in
            if book1.isDefault { return true }
            if book2.isDefault { return false }
            return book1.createdAt > book2.createdAt
        }
    }

    /// 获取默认生词本
    ///
    /// - Returns: 默认生词本对象，如果不存在返回nil
    func getDefaultBook() -> VocabularyBook? {
        let descriptor = FetchDescriptor<VocabularyBook>(
            predicate: #Predicate { $0.isDefault == true }
        )
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - 生词本管理

    /// 创建生词本
    ///
    /// - Parameters:
    ///   - name: 生词本名称
    ///   - isDefault: 是否设为默认生词本（默认false）
    /// - Returns: 创建的生词本对象
    ///
    /// **注意：**
    /// - 如果设为默认生词本，会自动取消其他生词本的默认状态
    @discardableResult
    func createBook(name: String, isDefault: Bool = false) -> VocabularyBook {
        // 如果要设为默认，先取消其他生词本的默认状态
        if isDefault {
            let allBooks = getAllBooks()
            for book in allBooks {
                book.isDefault = false
            }
        }

        let book = VocabularyBook(name: name, isDefault: isDefault)
        modelContext.insert(book)
        try? modelContext.save()

        return book
    }

    /// 重命名生词本
    ///
    /// - Parameters:
    ///   - book: 要重命名的生词本
    ///   - newName: 新名称
    func renameBook(_ book: VocabularyBook, to newName: String) {
        book.name = newName
        try? modelContext.save()
    }

    /// 删除生词本
    ///
    /// - Parameter book: 要删除的生词本
    ///
    /// **删除后的默认生词本维护：**
    /// 系统保证：任何时候都必须有一个默认生词本
    /// 1. 如果删除的是默认生词本且还有其他生词本：
    ///    - 先将排在第一位的其他生词本设为默认
    ///    - 然后删除原默认生词本
    /// 2. 如果删除后没有生词本：
    ///    - 自动创建新的默认生词本
    /// 3. 如果删除的是普通生词本：无特殊处理
    func deleteBook(_ book: VocabularyBook) {
        let wasDefault = book.isDefault

        // 如果删除的是默认生词本，需要先转移默认状态
        if wasDefault {
            let allBooks = getAllBooks()
            // 找到第一个非当前生词本的生词本
            let otherBooks = allBooks.filter { $0.id != book.id }

            if let newDefaultBook = otherBooks.first {
                // 先将第一个其他生词本设为默认
                newDefaultBook.isDefault = true
                try? modelContext.save()
            }
        }

        // 删除生词本（会级联删除所有单词）
        modelContext.delete(book)
        try? modelContext.save()

        // 确保系统中有默认生词本（如果删除后没有生词本，会自动创建）
        ensureDefaultBook()
    }

    /// 设置默认生词本
    ///
    /// - Parameter book: 要设为默认的生词本
    ///
    /// **行为：**
    /// - 取消其他所有生词本的默认状态
    /// - 将指定生词本设为默认
    func setDefaultBook(_ book: VocabularyBook) {
        let allBooks = getAllBooks()
        for b in allBooks {
            b.isDefault = false
        }
        book.isDefault = true
        try? modelContext.save()
    }

    // MARK: - 单词管理

    /// 添加单词到生词本
    ///
    /// - Parameters:
    ///   - word: 单词文本
    ///   - book: 目标生词本
    /// - Returns: 添加结果，成功返回true，重复返回false
    ///
    /// **重复检测：**
    /// - 如果单词已存在于该生词本中，返回false，不添加
    /// - 大小写敏感比较
    @discardableResult
    func addWord(_ word: String, to book: VocabularyBook) -> Bool {
        // 检查是否已存在
        if book.words.contains(where: { $0.word == word }) {
            return false
        }

        let bookWord = VocabularyBookWord(word: word)
        bookWord.vocabularyBook = book
        book.words.append(bookWord)

        modelContext.insert(bookWord)
        try? modelContext.save()

        return true
    }

    /// 删除单词
    ///
    /// - Parameter word: 要删除的单词
    func deleteWord(_ word: VocabularyBookWord) {
        modelContext.delete(word)
        try? modelContext.save()
    }

    /// 修改单词
    ///
    /// - Parameters:
    ///   - word: 要修改的单词对象
    ///   - newText: 新的单词文本
    func updateWord(_ word: VocabularyBookWord, newText: String) {
        word.word = newText
        try? modelContext.save()
    }

    // MARK: - 默认生词本初始化

    /// 确保系统中有默认生词本
    ///
    /// **系统保证：** 任何时候都必须有一个默认生词本
    ///
    /// **调用时机：**
    /// 1. App启动时
    /// 2. 删除生词本后
    ///
    /// **行为：**
    /// - 如果没有生词本，创建一个新的默认生词本
    /// - 如果有生词本但没有默认生词本，将第一个设为默认
    ///
    /// **注意：**
    /// - 在删除默认生词本时，应该先转移默认状态再删除
    /// - 此方法主要用于处理"删除后没有生词本"的情况
    func ensureDefaultBook() {
        let allBooks = getAllBooks()

        if allBooks.isEmpty {
            // 没有生词本，创建一个默认生词本
            createBook(name: defaultBookName, isDefault: true)
        } else if allBooks.first(where: { $0.isDefault }) == nil {
            // 有生词本但没有默认生词本，将第一个设为默认
            // (这种情况通常不应该发生，但作为安全保障)
            allBooks.first?.isDefault = true
            try? modelContext.save()
        }
    }

    // MARK: - 导出功能

    /// 导出单个生词本为txt文件
    ///
    /// - Parameter book: 要导出的生词本
    /// - Returns: txt文件的临时URL，如果导出失败返回nil
    ///
    /// **文件格式：**
    /// - 每行一个单词
    /// - UTF-8编码
    /// - 按添加时间倒序排列（最新的在上面）
    ///
    /// **文件名格式：**
    /// - `生词本名称_YYYYMMDD.txt`
    func exportBookToTxt(_ book: VocabularyBook) -> URL? {
        // 按添加时间倒序排列
        let sortedWords = book.words.sorted { $0.addedAt > $1.addedAt }
        let content = sortedWords.map { $0.word }.joined(separator: "\n")

        // 生成文件名
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())
        let fileName = "\(book.name)_\(dateString).txt"

        // 写入临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("⚠️ [VocabularyBookService] 导出txt失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 导出多个生词本为zip文件
    ///
    /// - Parameter books: 要导出的生词本数组
    /// - Returns: zip文件的临时URL，如果导出失败返回nil
    ///
    /// **文件格式：**
    /// - 每个生词本生成一个txt文件
    /// - 所有txt文件打包为一个zip文件
    ///
    /// **zip文件名格式：**
    /// - `VocabMaster生词本_YYYYMMDD.zip`
    func exportBooksToZip(_ books: [VocabularyBook]) -> URL? {
        guard !books.isEmpty else { return nil }

        // 生成zip文件名
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())
        let zipFileName = "VocabMaster生词本_\(dateString).zip"

        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent(zipFileName)

        // 删除已存在的同名文件
        try? FileManager.default.removeItem(at: zipURL)

        // 导出每个生词本为txt
        var txtURLs: [URL] = []
        for book in books {
            if let txtURL = exportBookToTxt(book) {
                txtURLs.append(txtURL)
            }
        }

        guard !txtURLs.isEmpty else { return nil }

        // 打包为zip
        do {
            try ZIPUtility.zipFiles(txtURLs, to: zipURL)

            // 清理临时txt文件
            for url in txtURLs {
                try? FileManager.default.removeItem(at: url)
            }

            return zipURL
        } catch {
            print("⚠️ [VocabularyBookService] 打包zip失败: \(error.localizedDescription)")
            return nil
        }
    }
}
