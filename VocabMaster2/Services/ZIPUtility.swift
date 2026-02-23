//
//  ZIPUtility.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import zlib

/// ZIP文件解压工具
class ZIPUtility {

    enum ZIPError: Error, LocalizedError {
        case invalidZIPFile
        case decompressionFailed
        case unsupportedCompression

        var errorDescription: String? {
            switch self {
            case .invalidZIPFile: return "无效的ZIP文件"
            case .decompressionFailed: return "解压失败"
            case .unsupportedCompression: return "不支持的压缩格式"
            }
        }
    }

    /// 中央目录文件信息
    private struct CentralDirectoryEntry {
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// 解压ZIP文件到目标目录
    static func unzip(at sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let data = try Data(contentsOf: sourceURL)

        // 先解析中央目录获取文件的真实大小信息
        let centralDirectory = parseCentralDirectory(data)

        var offset = 0
        var fileCount = 0

        while offset < data.count - 4 {
            // 检查本地文件头签名 (0x04034b50)
            let signature = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }

            if signature == 0x04034b50 {
                // 解析本地文件头
                guard offset + 30 <= data.count else { break }

                var compressionMethod = data.subdata(in: offset+8..<offset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
                var compressedSize = Int(data.subdata(in: offset+18..<offset+22).withUnsafeBytes { $0.load(as: UInt32.self) })
                var uncompressedSize = Int(data.subdata(in: offset+22..<offset+26).withUnsafeBytes { $0.load(as: UInt32.self) })
                let fileNameLength = Int(data.subdata(in: offset+26..<offset+28).withUnsafeBytes { $0.load(as: UInt16.self) })
                let extraFieldLength = Int(data.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) })

                let fileNameStart = offset + 30
                let fileNameEnd = fileNameStart + fileNameLength

                guard fileNameEnd <= data.count else { break }

                let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
                guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                    offset += 30 + fileNameLength + extraFieldLength + compressedSize
                    continue
                }

                // 如果本地文件头中大小为0，从中央目录获取真实大小（Data Descriptor情况）
                if compressedSize == 0 || uncompressedSize == 0 {
                    if let cdEntry = centralDirectory[fileName] {
                        compressionMethod = cdEntry.compressionMethod
                        compressedSize = cdEntry.compressedSize
                        uncompressedSize = cdEntry.uncompressedSize
                    }
                }

                let dataStart = fileNameEnd + extraFieldLength
                let dataEnd = dataStart + compressedSize

                guard dataEnd <= data.count else { break }

                // 跳过目录
                if fileName.hasSuffix("/") {
                    let dirURL = destinationURL.appendingPathComponent(fileName)
                    try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
                    offset = dataEnd
                    continue
                }

                // 解压文件
                let compressedData = data.subdata(in: dataStart..<dataEnd)

                var fileData: Data
                if compressionMethod == 0 {
                    // 无压缩 (Stored)
                    fileData = compressedData
                } else if compressionMethod == 8 {
                    // Deflate压缩
                    if compressedSize == 0 && uncompressedSize == 0 {
                        // 空文件
                        fileData = Data()
                    } else {
                        fileData = try decompress(compressedData, uncompressedSize: uncompressedSize)
                    }
                } else {
                    // 不支持的压缩方法，跳过
                    offset = dataEnd
                    continue
                }

                // 获取文件名（去除目录前缀）
                let cleanFileName = (fileName as NSString).lastPathComponent
                if !cleanFileName.isEmpty && !cleanFileName.hasPrefix(".") {
                    let fileURL = destinationURL.appendingPathComponent(cleanFileName)

                    // 确保父目录存在
                    let parentDir = fileURL.deletingLastPathComponent()
                    try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

                    try fileData.write(to: fileURL)
                    fileCount += 1
                }

                offset = dataEnd
            } else if signature == 0x02014b50 {
                // 中央目录头，停止处理
                break
            } else {
                offset += 1
            }
        }
    }

    /// 解析中央目录获取所有文件的真实大小信息
    private static func parseCentralDirectory(_ data: Data) -> [String: CentralDirectoryEntry] {
        var entries: [String: CentralDirectoryEntry] = [:]

        // 从文件末尾查找End of Central Directory (EOCD)记录
        // EOCD签名: 0x06054b50
        var eocdOffset = -1
        let searchStart = data.count - 22
        let searchEnd = max(0, data.count - 65557)

        for i in stride(from: searchStart, through: searchEnd, by: -1) {
            if i + 4 <= data.count {
                let sig = data.subdata(in: i..<i+4).withUnsafeBytes { $0.load(as: UInt32.self) }
                if sig == 0x06054b50 {
                    eocdOffset = i
                    break
                }
            }
        }

        guard eocdOffset >= 0, eocdOffset + 22 <= data.count else {
            return entries
        }

        // 从EOCD获取中央目录偏移
        let cdOffset = Int(data.subdata(in: eocdOffset+16..<eocdOffset+20).withUnsafeBytes { $0.load(as: UInt32.self) })

        var offset = cdOffset
        var entryCount = 0
        while offset < data.count - 4 {
            let signature = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }

            if signature != 0x02014b50 {
                break
            }

            guard offset + 46 <= data.count else {
                break
            }

            let compressionMethod = data.subdata(in: offset+10..<offset+12).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compressedSize = Int(data.subdata(in: offset+20..<offset+24).withUnsafeBytes { $0.load(as: UInt32.self) })
            let uncompressedSize = Int(data.subdata(in: offset+24..<offset+28).withUnsafeBytes { $0.load(as: UInt32.self) })
            let fileNameLength = Int(data.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) })
            let extraFieldLength = Int(data.subdata(in: offset+30..<offset+32).withUnsafeBytes { $0.load(as: UInt16.self) })
            let commentLength = Int(data.subdata(in: offset+32..<offset+34).withUnsafeBytes { $0.load(as: UInt16.self) })
            let localHeaderOffset = Int(data.subdata(in: offset+42..<offset+46).withUnsafeBytes { $0.load(as: UInt32.self) })

            let fileNameStart = offset + 46
            let fileNameEnd = fileNameStart + fileNameLength

            guard fileNameEnd <= data.count else {
                break
            }

            let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
            if let fileName = String(data: fileNameData, encoding: .utf8) {
                entries[fileName] = CentralDirectoryEntry(
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
                entryCount += 1
            }

            offset = fileNameEnd + extraFieldLength + commentLength
        }

        return entries
    }

    /// 使用Deflate算法解压数据 (raw deflate, 无zlib header)
    private static func decompress(_ compressedData: Data, uncompressedSize: Int) throws -> Data {
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
        defer { destinationBuffer.deallocate() }

        var stream = z_stream()
        var totalOut: UInt = 0

        try compressedData.withUnsafeBytes { sourcePtr in
            guard let sourceBase = sourcePtr.baseAddress else {
                throw ZIPError.decompressionFailed
            }

            stream.next_in = UnsafeMutablePointer(mutating: sourceBase.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = uInt(compressedData.count)
            stream.next_out = destinationBuffer
            stream.avail_out = uInt(uncompressedSize)

            // -MAX_WBITS (-15) 表示 raw deflate (无 zlib header)
            let initResult = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initResult == Z_OK else {
                throw ZIPError.decompressionFailed
            }

            let inflateResult = inflate(&stream, Z_FINISH)
            totalOut = stream.total_out
            inflateEnd(&stream)

            if inflateResult != Z_STREAM_END && inflateResult != Z_OK {
                throw ZIPError.decompressionFailed
            }
        }

        return Data(bytes: destinationBuffer, count: Int(totalOut))
    }

    // MARK: - 压缩方法

    /// 将多个文件打包为ZIP文件
    ///
    /// - Parameters:
    ///   - fileURLs: 要打包的文件URL列表
    ///   - zipURL: 目标ZIP文件URL
    /// - Throws: ZIPError 如果打包失败
    static func zipFiles(_ fileURLs: [URL], to zipURL: URL) throws {
        var zipData = Data()

        // 存储中央目录条目信息
        var centralDirectoryEntries: [(fileName: String, localHeaderOffset: Int, compressedSize: Int, uncompressedSize: Int, crc32: UInt32)] = []

        // 写入每个文件的本地文件头和数据
        for fileURL in fileURLs {
            let fileName = fileURL.lastPathComponent
            let fileData = try Data(contentsOf: fileURL)
            let uncompressedSize = fileData.count

            // 计算CRC32
            let crc32 = calculateCRC32(fileData)

            // 压缩数据（使用Deflate）
            let compressedData = try compress(fileData)
            let compressedSize = compressedData.count

            // 记录当前本地文件头的偏移
            let localHeaderOffset = zipData.count

            // 写入本地文件头
            zipData.append(writeLocalFileHeader(
                fileName: fileName,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                crc32: crc32
            ))

            // 写入文件名
            zipData.append(fileName.data(using: .utf8)!)

            // 写入压缩数据
            zipData.append(compressedData)

            // 保存中央目录条目信息
            centralDirectoryEntries.append((
                fileName: fileName,
                localHeaderOffset: localHeaderOffset,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                crc32: crc32
            ))
        }

        // 记录中央目录的起始偏移
        let centralDirectoryOffset = zipData.count

        // 写入中央目录
        for entry in centralDirectoryEntries {
            zipData.append(writeCentralDirectoryHeader(
                fileName: entry.fileName,
                localHeaderOffset: entry.localHeaderOffset,
                compressedSize: entry.compressedSize,
                uncompressedSize: entry.uncompressedSize,
                crc32: entry.crc32
            ))

            // 写入文件名
            zipData.append(entry.fileName.data(using: .utf8)!)
        }

        // 计算中央目录大小
        let centralDirectorySize = zipData.count - centralDirectoryOffset

        // 写入End of Central Directory (EOCD)
        zipData.append(writeEndOfCentralDirectory(
            entryCount: centralDirectoryEntries.count,
            centralDirectorySize: centralDirectorySize,
            centralDirectoryOffset: centralDirectoryOffset
        ))

        // 写入ZIP文件
        try zipData.write(to: zipURL)
    }

    /// 写入本地文件头
    private static func writeLocalFileHeader(fileName: String, compressedSize: Int, uncompressedSize: Int, crc32: UInt32) -> Data {
        var data = Data()

        // 本地文件头签名 (0x04034b50)
        data.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])

        // 解压所需版本 (2.0)
        data.append(contentsOf: [0x14, 0x00])

        // 通用位标志
        data.append(contentsOf: [0x00, 0x00])

        // 压缩方法 (8 = Deflate)
        data.append(contentsOf: [0x08, 0x00])

        // 文件最后修改时间 (MS-DOS格式)
        data.append(contentsOf: [0x00, 0x00])

        // 文件最后修改日期 (MS-DOS格式)
        data.append(contentsOf: [0x21, 0x00])

        // CRC-32
        data.append(UInt32ToBytes(crc32))

        // 压缩大小
        data.append(UInt32ToBytes(UInt32(compressedSize)))

        // 未压缩大小
        data.append(UInt32ToBytes(UInt32(uncompressedSize)))

        // 文件名长度
        let fileNameLength = UInt16(fileName.utf8.count)
        data.append(UInt16ToBytes(fileNameLength))

        // 扩展字段长度
        data.append(contentsOf: [0x00, 0x00])

        return data
    }

    /// 写入中央目录文件头
    private static func writeCentralDirectoryHeader(fileName: String, localHeaderOffset: Int, compressedSize: Int, uncompressedSize: Int, crc32: UInt32) -> Data {
        var data = Data()

        // 中央目录文件头签名 (0x02014b50)
        data.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])

        // 压缩使用的版本 (2.0)
        data.append(contentsOf: [0x14, 0x00])

        // 解压所需版本 (2.0)
        data.append(contentsOf: [0x14, 0x00])

        // 通用位标志
        data.append(contentsOf: [0x00, 0x00])

        // 压缩方法 (8 = Deflate)
        data.append(contentsOf: [0x08, 0x00])

        // 文件最后修改时间
        data.append(contentsOf: [0x00, 0x00])

        // 文件最后修改日期
        data.append(contentsOf: [0x21, 0x00])

        // CRC-32
        data.append(UInt32ToBytes(crc32))

        // 压缩大小
        data.append(UInt32ToBytes(UInt32(compressedSize)))

        // 未压缩大小
        data.append(UInt32ToBytes(UInt32(uncompressedSize)))

        // 文件名长度
        let fileNameLength = UInt16(fileName.utf8.count)
        data.append(UInt16ToBytes(fileNameLength))

        // 扩展字段长度
        data.append(contentsOf: [0x00, 0x00])

        // 文件注释长度
        data.append(contentsOf: [0x00, 0x00])

        // 文件开始位置的磁盘编号
        data.append(contentsOf: [0x00, 0x00])

        // 内部文件属性
        data.append(contentsOf: [0x00, 0x00])

        // 外部文件属性
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // 本地文件头的偏移
        data.append(UInt32ToBytes(UInt32(localHeaderOffset)))

        return data
    }

    /// 写入End of Central Directory
    private static func writeEndOfCentralDirectory(entryCount: Int, centralDirectorySize: Int, centralDirectoryOffset: Int) -> Data {
        var data = Data()

        // EOCD签名 (0x06054b50)
        data.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])

        // 当前磁盘编号
        data.append(contentsOf: [0x00, 0x00])

        // 中央目录开始位置的磁盘编号
        data.append(contentsOf: [0x00, 0x00])

        // 本磁盘上的中央目录记录数
        data.append(UInt16ToBytes(UInt16(entryCount)))

        // 中央目录记录总数
        data.append(UInt16ToBytes(UInt16(entryCount)))

        // 中央目录大小
        data.append(UInt32ToBytes(UInt32(centralDirectorySize)))

        // 中央目录偏移
        data.append(UInt32ToBytes(UInt32(centralDirectoryOffset)))

        // ZIP文件注释长度
        data.append(contentsOf: [0x00, 0x00])

        return data
    }

    /// 使用Deflate算法压缩数据
    private static func compress(_ data: Data) throws -> Data {
        let bufferSize = deflateBound(nil, UInt(data.count))
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferSize))
        defer { destinationBuffer.deallocate() }

        var stream = z_stream()
        var compressedSize: UInt = 0

        try data.withUnsafeBytes { sourcePtr in
            guard let sourceBase = sourcePtr.baseAddress else {
                throw ZIPError.decompressionFailed
            }

            stream.next_in = UnsafeMutablePointer(mutating: sourceBase.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = uInt(data.count)
            stream.next_out = destinationBuffer
            stream.avail_out = uInt(bufferSize)

            // -MAX_WBITS (-15) 表示 raw deflate (无 zlib header)
            let initResult = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initResult == Z_OK else {
                throw ZIPError.decompressionFailed
            }

            let deflateResult = deflate(&stream, Z_FINISH)
            compressedSize = stream.total_out
            deflateEnd(&stream)

            if deflateResult != Z_STREAM_END {
                throw ZIPError.decompressionFailed
            }
        }

        return Data(bytes: destinationBuffer, count: Int(compressedSize))
    }

    /// 计算CRC32校验和
    private static func calculateCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0
        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            crc = UInt32(crc32(0, baseAddress.assumingMemoryBound(to: UInt8.self), uInt(data.count)))
        }
        return crc
    }

    /// 将UInt16转换为小端字节序
    private static func UInt16ToBytes(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: MemoryLayout<UInt16>.size)
    }

    /// 将UInt32转换为小端字节序
    private static func UInt32ToBytes(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: MemoryLayout<UInt32>.size)
    }
}
