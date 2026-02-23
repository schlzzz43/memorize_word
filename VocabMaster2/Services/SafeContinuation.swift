//
//  SafeContinuation.swift
//  VocabMaster2
//
//  Created on 2026/02/15.
//

import Foundation

/// 安全的Continuation包装器，防止重复resume和内存泄漏
@MainActor
class SafeContinuation<T> {
    private var continuation: CheckedContinuation<T, Never>?
    private var hasResumed = false

    /// 存储continuation
    func store(_ cont: CheckedContinuation<T, Never>) {
        assert(continuation == nil, "尝试存储新的continuation但之前的还未清理")
        continuation = cont
        hasResumed = false
    }

    /// 安全地resume continuation
    func resume(returning value: T) {
        guard let cont = continuation, !hasResumed else {
            print("⚠️ SafeContinuation: 尝试resume已经完成或不存在的continuation")
            return
        }

        continuation = nil
        hasResumed = true
        cont.resume(returning: value)
    }

    /// 清理continuation（用于取消操作）
    func cancel(returning value: T) {
        if let cont = continuation, !hasResumed {
            continuation = nil
            hasResumed = true
            cont.resume(returning: value)
        }
        continuation = nil
        hasResumed = false
    }

    /// 检查是否有活跃的continuation
    var isActive: Bool {
        continuation != nil && !hasResumed
    }
}
