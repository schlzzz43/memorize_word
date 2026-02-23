//
//  SelectableTextView.swift
//  VocabMaster2
//
//  精确单词选择组件 - UIViewRepresentable 包装 UITextView
//  支持长按识别单词，自动处理连字符、撇号和标点符号
//

import SwiftUI
import UIKit

/// 可选择文本视图 - 支持长按精确识别单词
struct SelectableTextView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let backgroundColor: UIColor
    let textAlignment: NSTextAlignment
    let onWordSelected: (String) -> Void

    /// 便捷初始化方法 - 使用默认配置
    init(
        text: String,
        font: UIFont = .preferredFont(forTextStyle: .body),
        textColor: UIColor = .label,
        backgroundColor: UIColor = .clear,
        textAlignment: NSTextAlignment = .left,
        onWordSelected: @escaping (String) -> Void
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.textAlignment = textAlignment
        self.onWordSelected = onWordSelected
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        // 基础配置
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        // 样式配置
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = backgroundColor
        textView.textAlignment = textAlignment

        // 添加长按手势
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        textView.addGestureRecognizer(longPress)

        // 设置协调器
        context.coordinator.textView = textView

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // 只在值变化时更新，避免频繁重建
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.font != font {
            uiView.font = font
        }
        if uiView.textColor != textColor {
            uiView.textColor = textColor
        }
        if uiView.backgroundColor != backgroundColor {
            uiView.backgroundColor = backgroundColor
        }
        if uiView.textAlignment != textAlignment {
            uiView.textAlignment = textAlignment
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let layoutManager = uiView.layoutManager
        let textContainer = uiView.textContainer

        // 关键修复：设置textContainer的宽度约束，使其正确计算多行文本
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)

        // 确保布局完成
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)

        return CGSize(width: width, height: usedRect.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var parent: SelectableTextView
        weak var textView: UITextView?

        init(parent: SelectableTextView) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            // 只在手势开始时处理
            guard gesture.state == .began else { return }
            guard let textView = textView else { return }

            // 获取点击位置
            let location = gesture.location(in: textView)

            // 获取点击位置对应的字符索引
            let textContainer = textView.textContainer
            let layoutManager = textView.layoutManager
            let characterIndex = layoutManager.characterIndex(
                for: location,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            // 检查索引有效性
            guard characterIndex < textView.text.count else { return }

            // 提取单词
            if let word = extractWord(from: textView.text, at: characterIndex) {
                // 触觉反馈
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                // 触发回调
                parent.onWordSelected(word)

                // 清除选中状态
                textView.selectedTextRange = nil
            }
        }

        /// 从文本中提取指定位置的单词
        /// - Parameters:
        ///   - text: 完整文本
        ///   - index: 字符索引
        /// - Returns: 提取的单词，如果点击位置不是单词则返回 nil
        private func extractWord(from text: String, at index: Int) -> String? {
            guard index >= 0 && index < text.count else { return nil }

            let characters = Array(text)

            // 检查是否是中日文字符
            if isCJKCharacter(characters[index]) {
                // 中日文只返回单个字符
                return String(characters[index])
            }

            // 定义单词字符集：字母 + 连字符 + 撇号
            let wordCharacters = CharacterSet.letters
                .union(CharacterSet(charactersIn: "-'"))

            // 检查点击位置是否在单词上
            let clickedChar = String(characters[index])
            guard clickedChar.unicodeScalars.allSatisfy({ wordCharacters.contains($0) }) else {
                return nil
            }

            // 向前扩展到单词开始
            var startIndex = index
            while startIndex > 0 {
                let prevChar = String(characters[startIndex - 1])
                if prevChar.unicodeScalars.allSatisfy({ wordCharacters.contains($0) }) {
                    startIndex -= 1
                } else {
                    break
                }
            }

            // 向后扩展到单词结束
            var endIndex = index
            while endIndex < characters.count - 1 {
                let nextChar = String(characters[endIndex + 1])
                if nextChar.unicodeScalars.allSatisfy({ wordCharacters.contains($0) }) {
                    endIndex += 1
                } else {
                    break
                }
            }

            // 提取单词
            let word = String(characters[startIndex...endIndex])

            // 清理首尾标点符号
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)

            return cleaned.isEmpty ? nil : cleaned
        }

        /// 检查字符是否是中日文字符
        private func isCJKCharacter(_ char: Character) -> Bool {
            char.unicodeScalars.contains { scalar in
                let value = scalar.value
                return (0x4E00...0x9FFF).contains(value) ||  // 中文
                       (0x3040...0x309F).contains(value) ||  // 平假名
                       (0x30A0...0x30FF).contains(value)     // 片假名
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        Text("SelectableTextView 测试")
            .font(.headline)

        SelectableTextView(
            text: "I eat an apple. This is a long-term plan for teacher's benefit.",
            font: .preferredFont(forTextStyle: .body),
            textColor: .label,
            backgroundColor: .clear
        ) { word in
            // Selected: \(word)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)

        SelectableTextView(
            text: "我吃一个苹果。This is mixed text.",
            font: .preferredFont(forTextStyle: .body),
            textColor: .label,
            backgroundColor: .clear
        ) { word in
            // Selected: \(word)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)

        Text("长按文本中的单词测试选择功能")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
}
