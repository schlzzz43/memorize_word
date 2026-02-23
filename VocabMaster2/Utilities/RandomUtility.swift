//
//  RandomUtility.swift
//  VocabMaster2
//
//  Created on 2026/02/17.
//

import Foundation

/// 增强的随机工具，使用时间戳增强随机性
extension Array {
    /// 增强的随机打乱（使用纳秒级时间戳增强随机性）
    /// - Returns: 打乱后的数组
    func enhancedShuffled() -> [Element] {
        guard !isEmpty else { return self }

        // 获取当前时间的纳秒级时间戳
        let nanoTime = DispatchTime.now().uptimeNanoseconds

        // 基于纳秒时间戳计算打乱次数（2-4次）
        let shuffleCount = Int((nanoTime % 3) + 2)

        var result = self
        for _ in 0..<shuffleCount {
            result = result.shuffled()
        }

        return result
    }

    /// 增强的随机元素选择（使用时间戳增强随机性）
    /// - Returns: 随机选择的元素，如果数组为空则返回 nil
    func enhancedRandomElement() -> Element? {
        guard !isEmpty else { return nil }

        // 使用纳秒时间戳增加随机性
        let nanoTime = DispatchTime.now().uptimeNanoseconds
        let index = Int((nanoTime ^ UInt64(self.count)) % UInt64(self.count))

        return self[index]
    }
}

/// 随机数工具类
struct RandomUtility {
    /// 使用时间戳增强的随机整数
    /// - Parameters:
    ///   - range: 范围
    /// - Returns: 随机整数
    static func enhancedRandom(in range: Range<Int>) -> Int {
        let nanoTime = DispatchTime.now().uptimeNanoseconds
        let baseRandom = Int.random(in: range)

        // 使用纳秒时间戳进一步混合
        let enhanced = (baseRandom + Int(nanoTime % UInt64(range.count))) % range.count
        return range.lowerBound + enhanced
    }

    /// 使用时间戳增强的随机浮点数
    /// - Parameters:
    ///   - range: 范围
    /// - Returns: 随机浮点数
    static func enhancedRandom(in range: Range<Double>) -> Double {
        let nanoTime = DispatchTime.now().uptimeNanoseconds
        let baseRandom = Double.random(in: range)

        // 使用纳秒时间戳进一步混合（保持在范围内）
        let timeOffset = Double(nanoTime % 1000) / 1000.0
        let rangeSize = range.upperBound - range.lowerBound
        let enhanced = (baseRandom + timeOffset * rangeSize).truncatingRemainder(dividingBy: rangeSize)

        return range.lowerBound + enhanced
    }
}
