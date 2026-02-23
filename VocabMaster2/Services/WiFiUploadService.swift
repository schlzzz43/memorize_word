//
//  WiFiUploadService.swift
//  VocabMaster2
//
//  Created on 2026/01/24.
//

import Foundation
import Network
import Combine

/// WiFi上传服务（单例，支持词库和习题）
class WiFiUploadService: ObservableObject {
    static let shared = WiFiUploadService()

    @Published var isRunning = false
    @Published var serverAddress: String = ""
    @Published var uploadProgress: Double = 0
    @Published var uploadStatus: String = ""
    @Published var lastUploadedFile: URL?
    @Published var hasActiveConnection = false

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let port: UInt16 = 8080
    private let maxFileSize: Int = 500 * 1024 * 1024 // 500MB

    var onVocabularyFileReceived: ((URL, String) -> Void)?  // (fileURL, originalFileName) 词库ZIP文件回调
    var onExerciseFileReceived: ((URL, String) -> Void)?  // (fileURL, originalFileName) 习题TXT文件回调

    private init() {}

    /// 获取本机IP地址
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else {
            print("❌ [WiFiUploadService] 无法获取网络接口信息")
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)

                // 优先选择en0，但也接受其他en*接口（如en1, en2）
                // 排除回环地址127.0.0.1
                if ip != "127.0.0.1" {
                    if name == "en0" {
                        address = ip
                        break
                    } else if name.hasPrefix("en") && address == nil {
                        address = ip
                    }
                }
            }
        }

        if address == nil {
            print("❌ [WiFiUploadService] 未找到有效的IP地址")
        }

        return address
    }

    /// 启动服务器
    func start() {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))

            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        if let ip = self?.getLocalIPAddress() {
                            self?.serverAddress = "http://\(ip):\(self?.port ?? 8080)"
                        } else {
                            self?.serverAddress = ""
                            self?.uploadStatus = "无法获取IP地址，请检查WiFi连接"
                        }
                        if self?.serverAddress != "" {
                            self?.uploadStatus = "等待连接..."
                        }
                    case .failed(let error):
                        print("❌ [WiFiUploadService] 监听器启动失败: \(error.localizedDescription)")
                        self?.isRunning = false
                        self?.uploadStatus = "启动失败: \(error.localizedDescription)"
                    case .cancelled:
                        self?.isRunning = false
                        self?.uploadStatus = "服务已停止"
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: .main)

        } catch {
            print("❌ [WiFiUploadService] 无法创建监听器: \(error.localizedDescription)")
            uploadStatus = "启动失败: \(error.localizedDescription)"
        }
    }

    /// 停止服务器
    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
        isRunning = false
        hasActiveConnection = false
        serverAddress = ""
        uploadStatus = ""
    }

    /// 处理连接
    private func handleConnection(_ connection: NWConnection) {
        // 检查是否已有活动连接
        if hasActiveConnection {
            connection.cancel()
            return
        }

        activeConnection = connection
        hasActiveConnection = true

        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.uploadStatus = "设备已连接"
                    self?.receiveHTTPRequest(connection)
                case .failed(let error):
                    print("❌ [WiFiUploadService] 连接失败: \(error.localizedDescription)")
                    self?.hasActiveConnection = false
                    self?.activeConnection = nil
                    self?.uploadStatus = "等待连接..."
                case .cancelled:
                    self?.hasActiveConnection = false
                    self?.activeConnection = nil
                    self?.uploadStatus = "等待连接..."
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private var receivedData = Data()
    private var expectedContentLength: Int = 0
    private var isReceivingPost = false

    /// 接收HTTP请求
    private func receiveHTTPRequest(_ connection: NWConnection) {
        // 重置接收状态
        receivedData = Data()
        expectedContentLength = 0
        isReceivingPost = false

        receiveData(connection)
    }

    private func receiveData(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [WiFiUploadService] 数据接收失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.uploadStatus = "接收失败: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data, !data.isEmpty else { return }

            self.receivedData.append(data)

            // 检查是否超过最大文件大小限制
            if self.receivedData.count > self.maxFileSize {
                print("❌ [WiFiUploadService] 文件大小超限: \(self.receivedData.count) bytes")
                DispatchQueue.main.async {
                    self.uploadStatus = "文件过大（超过500MB）"
                }
                self.sendResponse(connection, status: "413 Payload Too Large", body: "文件过大，最大支持500MB")
                return
            }

            // 第一次接收时解析请求类型
            if !self.isReceivingPost {
                if let request = String(data: self.receivedData.prefix(500), encoding: .utf8) {
                    if request.hasPrefix("GET") {
                        self.sendUploadPage(connection)
                        return
                    } else if request.hasPrefix("POST") {
                        self.isReceivingPost = true

                        // 解析Content-Length
                        if let contentLengthRange = request.range(of: "Content-Length: "),
                           let endRange = request.range(of: "\r\n", range: contentLengthRange.upperBound..<request.endIndex) {
                            let lengthStr = String(request[contentLengthRange.upperBound..<endRange.lowerBound])
                            self.expectedContentLength = Int(lengthStr) ?? 0
                        }

                        DispatchQueue.main.async {
                            self.uploadStatus = "正在接收文件..."
                        }
                    }
                }
            }

            // 如果是POST请求，检查是否接收完整
            if self.isReceivingPost {
                // 查找header结束位置
                if let headerEnd = self.receivedData.range(of: "\r\n\r\n".data(using: .utf8)!) {
                    let bodyLength = self.receivedData.count - headerEnd.upperBound

                    // 检查是否接收完整（允许一定误差，或者检测到ZIP结束标记）
                    let hasZipEnd = self.findZipEnd(in: self.receivedData)

                    if bodyLength >= self.expectedContentLength || hasZipEnd || isComplete {
                        self.handleFileUpload(data: self.receivedData, connection: connection)
                        return
                    }
                }

                // 继续接收
                self.receiveData(connection)
            } else if isComplete {
                self.receiveHTTPRequest(connection)
            } else {
                // 继续接收以获取完整请求头
                self.receiveData(connection)
            }
        }
    }

    /// 查找ZIP文件结束标记
    private func findZipEnd(in data: Data) -> Bool {
        // ZIP End of Central Directory signature: 0x06054b50 (little-endian: 50 4B 05 06)
        let endSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        guard data.count >= 22 else { return false } // 最小EOCD大小

        // 从后向前搜索（EOCD通常在文件末尾）
        let searchStart = max(0, data.count - 65557) // EOCD最大可能位置
        for i in stride(from: data.count - 22, through: searchStart, by: -1) {
            if data[data.startIndex + i] == endSignature[0] &&
               data[data.startIndex + i + 1] == endSignature[1] &&
               data[data.startIndex + i + 2] == endSignature[2] &&
               data[data.startIndex + i + 3] == endSignature[3] {
                return true
            }
        }
        return false
    }

    /// 发送上传页面
    private func sendUploadPage(_ connection: NWConnection) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>背单词 - 文件上传</title>
            <style>
                body { font-family: -apple-system, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; }
                h1 { color: #333; }
                .upload-area { border: 2px dashed #ccc; border-radius: 10px; padding: 40px; text-align: center; cursor: pointer; }
                .upload-area:hover { border-color: #007AFF; background: #f0f8ff; }
                .upload-area.dragover { border-color: #007AFF; background: #e6f3ff; }
                input[type="file"] { display: none; }
                .btn { background: #007AFF; color: white; padding: 12px 24px; border: none; border-radius: 8px; cursor: pointer; font-size: 16px; }
                .btn:hover { background: #0056b3; }
                .status { margin-top: 20px; padding: 10px; border-radius: 5px; }
                .success { background: #d4edda; color: #155724; }
                .error { background: #f8d7da; color: #721c24; }
                .info { background: #cce5ff; color: #004085; }
                .hint { margin-top: 20px; padding: 15px; background: #f8f9fa; border-radius: 8px; font-size: 14px; color: #666; }
            </style>
        </head>
        <body>
            <h1>📚 背单词 文件上传</h1>
            <p>请选择或拖拽文件到下方区域</p>
            <div class="upload-area" id="dropZone" onclick="document.getElementById('fileInput').click()">
                <p>📁 点击选择文件或拖拽到此处</p>
                <p style="color:#888">支持ZIP（词库）和TXT（习题），最大500MB</p>
            </div>
            <input type="file" id="fileInput" accept=".zip,.txt" onchange="uploadFile(this.files[0])">
            <div id="status"></div>

            <div class="hint">
                <strong>📖 文件格式说明：</strong><br>
                • <strong>词库文件</strong>：ZIP格式，包含词库txt和音频文件<br>
                • <strong>习题文件</strong>：TXT格式，每行9个字段用|分隔
            </div>

            <script>
                const dropZone = document.getElementById('dropZone');
                const statusDiv = document.getElementById('status');

                dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.classList.add('dragover'); });
                dropZone.addEventListener('dragleave', e => { dropZone.classList.remove('dragover'); });
                dropZone.addEventListener('drop', e => {
                    e.preventDefault();
                    dropZone.classList.remove('dragover');
                    const file = e.dataTransfer.files[0];
                    if (file) uploadFile(file);
                });

                function uploadFile(file) {
                    const fileName = file.name.toLowerCase();
                    if (!fileName.endsWith('.zip') && !fileName.endsWith('.txt')) {
                        showStatus('仅支持ZIP（词库）或TXT（习题）格式', 'error');
                        return;
                    }

                    const fileType = fileName.endsWith('.txt') ? '习题' : '词库';
                    showStatus('正在上传' + fileType + '文件...', 'info');

                    const formData = new FormData();
                    formData.append('file', file, file.name);

                    fetch('/upload', {
                        method: 'POST',
                        body: formData
                    })
                    .then(res => res.text())
                    .then(msg => showStatus(msg, 'success'))
                    .catch(err => showStatus('上传失败: ' + err, 'error'));
                }

                function showStatus(msg, type) {
                    statusDiv.innerHTML = '<div class="status ' + type + '">' + msg + '</div>';
                }
            </script>
        </body>
        </html>
        """

        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { error in
            self.receiveHTTPRequest(connection)
        })
    }

    /// 处理文件上传
    private func handleFileUpload(data: Data, connection: NWConnection) {
        DispatchQueue.main.async {
            self.uploadStatus = "正在处理上传..."
        }

        // 提取boundary和原始文件名
        var boundary: String?
        var originalFileName: String?
        if let headerEnd = data.range(of: "\r\n\r\n".data(using: .utf8)!) {
            if let headerString = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) {
                // 提取boundary
                if let boundaryRange = headerString.range(of: "boundary=") {
                    var boundaryValue = String(headerString[boundaryRange.upperBound...])
                    if let endRange = boundaryValue.range(of: "\r\n") {
                        boundaryValue = String(boundaryValue[..<endRange.lowerBound])
                    }
                    boundary = boundaryValue.trimmingCharacters(in: .whitespaces)
                }
            }
        }

        // 从multipart body中提取原始文件名
        if let httpHeaderEnd = data.range(of: "\r\n\r\n".data(using: .utf8)!) {
            let bodyStart = httpHeaderEnd.upperBound
            let bodyData = data[bodyStart...]

            if let boundaryData = boundary?.data(using: .utf8),
               let boundaryRange = bodyData.range(of: boundaryData) {
                let searchStart = boundaryRange.upperBound
                if let headerEnd = bodyData[searchStart...].range(of: "\r\n\r\n".data(using: .utf8)!) {
                    let multipartHeader = bodyData[searchStart..<headerEnd.lowerBound]

                    if let headerString = String(data: multipartHeader, encoding: .utf8) {
                        // 查找 filename="..."
                        if let filenameRange = headerString.range(of: "filename=\"") {
                            let afterFilename = String(headerString[filenameRange.upperBound...])
                            if let endQuote = afterFilename.firstIndex(of: "\"") {
                                var extractedName = String(afterFilename[..<endQuote])
                                // 清理路径分隔符，只保留文件名
                                if let lastSlash = extractedName.lastIndex(of: "/") {
                                    extractedName = String(extractedName[extractedName.index(after: lastSlash)...])
                                }
                                if let lastBackslash = extractedName.lastIndex(of: "\\") {
                                    extractedName = String(extractedName[extractedName.index(after: lastBackslash)...])
                                }
                                originalFileName = extractedName
                            }
                        }
                    }
                }
            }
        }

        // 判断文件类型（基于文件名后缀）
        let fileName = originalFileName ?? "upload_\(Date().timeIntervalSince1970)"
        let isZipFile = fileName.lowercased().hasSuffix(".zip")
        let isTxtFile = fileName.lowercased().hasSuffix(".txt")

        // 提取文件数据
        var fileData: Data?

        if isZipFile {
            // ZIP文件：查找ZIP签名
            guard let zipStart = findZipStart(in: data) else {
                print("❌ [WiFiUploadService] 无效的ZIP文件（未找到ZIP签名）")
                sendResponse(connection, status: "400 Bad Request", body: "无效的ZIP文件")
                return
            }

            // 提取ZIP数据，需要找到结束位置（multipart boundary之前）
            var zipData = data.suffix(from: zipStart)

            // 查找multipart结束边界
            if let boundary = boundary {
                let endBoundary = "--\(boundary)".data(using: .utf8)!
                if let endRange = zipData.range(of: endBoundary) {
                    // 边界前通常有\r\n
                    var endIndex = endRange.lowerBound
                    if endIndex >= zipData.startIndex + 2 {
                        let beforeBoundary = zipData[zipData.index(endIndex, offsetBy: -2)..<endIndex]
                        if beforeBoundary == "\r\n".data(using: .utf8)! {
                            endIndex = zipData.index(endIndex, offsetBy: -2)
                        }
                    }
                    zipData = zipData[zipData.startIndex..<endIndex]
                }
            }
            fileData = zipData

        } else if isTxtFile {
            // TXT文件：从multipart body中提取文本数据
            if let httpHeaderEnd = data.range(of: "\r\n\r\n".data(using: .utf8)!) {
                let bodyStart = httpHeaderEnd.upperBound
                let bodyData = data[bodyStart...]

                if let boundaryData = boundary?.data(using: .utf8),
                   let boundaryRange = bodyData.range(of: boundaryData) {
                    let searchStart = boundaryRange.upperBound

                    if let headerEnd = bodyData[searchStart...].range(of: "\r\n\r\n".data(using: .utf8)!) {
                        let contentStart = headerEnd.upperBound

                        let endBoundary = "--\(boundary ?? "")".data(using: .utf8)!
                        if let endRange = bodyData[contentStart...].range(of: endBoundary) {
                            var endIndex = endRange.lowerBound
                            if endIndex >= bodyData.startIndex + 2 {
                                let beforeBoundary = bodyData[bodyData.index(endIndex, offsetBy: -2)..<endIndex]
                                if beforeBoundary == "\r\n".data(using: .utf8)! {
                                    endIndex = bodyData.index(endIndex, offsetBy: -2)
                                }
                            }
                            fileData = Data(bodyData[contentStart..<endIndex])
                        }
                    }
                }
            }

            if fileData == nil {
                print("❌ [WiFiUploadService] 无法提取TXT文件数据")
                sendResponse(connection, status: "400 Bad Request", body: "无效的TXT文件")
                return
            }

        } else {
            if originalFileName == nil {
                sendResponse(connection, status: "400 Bad Request", body: "无法识别文件名，请确保上传的文件名包含 .txt 或 .zip 扩展名")
            } else {
                sendResponse(connection, status: "400 Bad Request", body: "不支持的文件类型（\(fileName)），仅支持ZIP（词库）或TXT（习题）")
            }
            return
        }

        guard let fileData = fileData else {
            print("❌ [WiFiUploadService] 文件数据提取失败")
            sendResponse(connection, status: "400 Bad Request", body: "文件数据提取失败")
            return
        }

        // 保存到临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(fileName)

        do {
            try fileData.write(to: tempFile)

            // 先发送响应，再处理文件
            let fileTypeDesc = isTxtFile ? "习题" : "词库"
            sendResponse(connection, status: "200 OK", body: "\(fileTypeDesc)上传成功！请在App中查看导入结果。")

            DispatchQueue.main.async {
                self.lastUploadedFile = tempFile
                self.uploadStatus = "上传成功，正在导入..."

                // 根据文件扩展名调用相应回调
                if isTxtFile {
                    self.onExerciseFileReceived?(tempFile, fileName)
                } else if isZipFile {
                    self.onVocabularyFileReceived?(tempFile, fileName)
                }
            }

        } catch {
            print("❌ [WiFiUploadService] 文件保存失败: \(error.localizedDescription)")
            sendResponse(connection, status: "500 Internal Server Error", body: "保存文件失败: \(error.localizedDescription)")
        }
    }

    /// 查找ZIP文件起始位置
    private func findZipStart(in data: Data) -> Data.Index? {
        let zipSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04] // PK..
        guard data.count >= 4 else { return nil }

        for i in 0..<(data.count - 4) {
            if data[data.startIndex + i] == zipSignature[0] &&
               data[data.startIndex + i + 1] == zipSignature[1] &&
               data[data.startIndex + i + 2] == zipSignature[2] &&
               data[data.startIndex + i + 3] == zipSignature[3] {
                return data.startIndex + i
            }
        }
        return nil
    }

    /// 发送HTTP响应
    private func sendResponse(_ connection: NWConnection, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/plain; charset=UTF-8\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            // POST请求完成后关闭连接，让浏览器能正确接收响应
            connection.cancel()
            DispatchQueue.main.async {
                self?.hasActiveConnection = false
                self?.activeConnection = nil
            }
        })
    }
}
