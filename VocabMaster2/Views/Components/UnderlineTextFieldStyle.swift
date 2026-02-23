//
//  UnderlineTextFieldStyle.swift
//  VocabMaster2
//
//  Created on 2026/02/11.
//

import SwiftUI

/// Custom TextField style with bottom underline only
struct UnderlineTextFieldStyle: TextFieldStyle {
    var focusColor: Color = .blue
    var unfocusedColor: Color = Color.gray.opacity(0.3)
    var isFocused: Bool = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration
                .padding(.vertical, 8)

            Rectangle()
                .fill(isFocused ? focusColor : unfocusedColor)
                .frame(height: 2)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
    }
}

/// View modifier wrapper that adds underline style with focus state tracking
struct UnderlineTextFieldModifier: ViewModifier {
    var isFocused: Bool
    var focusColor: Color = .blue
    var unfocusedColor: Color = Color.gray.opacity(0.3)

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .padding(.vertical, 8)

            Rectangle()
                .fill(isFocused ? focusColor : unfocusedColor)
                .frame(height: 2)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
    }
}

extension View {
    /// Applies underline text field style with focus animation
    /// - Parameters:
    ///   - isFocused: Binding to track focus state for color animation
    ///   - focusColor: Color when focused (default: blue)
    ///   - unfocusedColor: Color when unfocused (default: gray)
    func underlineTextField(isFocused: Bool, focusColor: Color = .blue, unfocusedColor: Color = Color.gray.opacity(0.3)) -> some View {
        self.modifier(UnderlineTextFieldModifier(isFocused: isFocused, focusColor: focusColor, unfocusedColor: unfocusedColor))
    }
}
