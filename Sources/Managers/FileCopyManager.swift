import Foundation

/// 文件复制进度回调
struct CopyProgress {
    let currentFile: String
    let currentFileProgress: Double  // 0-1
    let totalProgress: Double        // 0-1
    let filesCompleted: Int
    let filesTotal: Int
    let bytesCopied: Int64
    let bytesTotal: Int64
}

/// 文件复制管理器
final class FileCopyManager: ObservableObject {
    static let shared = FileCopyManager()
    private init() {}

    @Published var progress: CopyProgress?
    @Published var isCopying = false
    @Published var currentOperation: String = ""

    private var shouldCancel = false

    // 复制进度跟踪（使用实例属性避免 inout 参数在并发上下文中的问题）
    private var totalSize: Int64 = 0
    private var totalFiles: Int = 0
    private var bytesCopied: Int64 = 0
    private var filesCompleted: Int = 0

    /// 取消复制
    func cancel() {
        shouldCancel = true
    }

    /// 计算目录总大小和文件数量
    func calculateSize(of paths: [URL]) -> (totalSize: Int64, fileCount: Int) {
        var totalSize: Int64 = 0
        var fileCount = 0

        for path in paths {
            if let values = try? path.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
                // 遍历目录
                if let enumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
                    for case let fileURL as URL in enumerator {
                        guard let fileValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else { continue }
                        if fileValues.isDirectory != true {
                            totalSize += Int64(fileValues.fileSize ?? 0)
                            fileCount += 1
                        }
                    }
                }
            } else {
                if let values = try? path.resourceValues(forKeys: [.fileSizeKey]) {
                    totalSize += Int64(values.fileSize ?? 0)
                    fileCount += 1
                }
            }
        }

        return (totalSize, fileCount)
    }

    /// 复制文件/目录到目标路径
    func copyFiles(_ sourceURLs: [URL], to destinationURL: URL) async throws -> Bool {
        shouldCancel = false
        isCopying = true
        bytesCopied = 0
        filesCompleted = 0

        defer {
            isCopying = false
        }

        // 确保目标目录存在
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &isDir) {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }

        // 计算总大小和文件数
        let (size, count) = calculateSize(of: sourceURLs)
        totalSize = size
        totalFiles = count

        for sourceURL in sourceURLs {
            if shouldCancel {
                throw NSError(domain: "FileCopy", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户已取消复制"])
            }

            let fileName = sourceURL.lastPathComponent
            currentOperation = "正在复制：\(fileName)"

            let destURL = destinationURL.appendingPathComponent(fileName)

            if let values = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
                try await copyDirectory(sourceURL, to: destURL)
            } else {
                try await copySingleFile(sourceURL, to: destURL)
            }
        }

        progress = CopyProgress(
            currentFile: "完成",
            currentFileProgress: 1.0,
            totalProgress: 1.0,
            filesCompleted: filesCompleted,
            filesTotal: totalFiles,
            bytesCopied: bytesCopied,
            bytesTotal: totalSize
        )

        return true
    }

    /// 复制单个文件（带进度）
    private func copySingleFile(_ source: URL, to destination: URL) async throws {
        let fileManager = FileManager.default

        // 如果目标已存在，先删除
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        // 确保目标目录存在
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        // 以流的方式复制以支持进度
        guard let inputStream = InputStream(url: source) else {
            throw NSError(domain: "FileCopy", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法打开源文件：\(source.lastPathComponent)"])
        }
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw NSError(domain: "FileCopy", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法创建目标文件：\(destination.lastPathComponent)"])
        }
        guard let outputStream = OutputStream(url: destination, append: false) else {
            throw NSError(domain: "FileCopy", code: -4, userInfo: [NSLocalizedDescriptionKey: "无法写入目标文件：\(destination.lastPathComponent)"])
        }

        inputStream.open()
        outputStream.open()
        defer {
            inputStream.close()
            outputStream.close()
        }

        let fileSize = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let bufferSize = 1024 * 1024 // 1MB 缓冲
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var fileBytesCopied: Int64 = 0

        while inputStream.hasBytesAvailable {
            if shouldCancel {
                try? fileManager.removeItem(at: destination)
                throw NSError(domain: "FileCopy", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户已取消复制"])
            }

            let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                throw NSError(domain: "FileCopy", code: -5, userInfo: [NSLocalizedDescriptionKey: "读取文件失败：\(source.lastPathComponent)"])
            }
            if bytesRead == 0 { break }

            outputStream.write(buffer, maxLength: bytesRead)
            fileBytesCopied += Int64(bytesRead)
            bytesCopied += Int64(bytesRead)

            // 更新进度
            let fileProgress = fileSize > 0 ? Double(fileBytesCopied) / Double(fileSize) : 1.0
            let totalProgress = totalSize > 0 ? Double(bytesCopied) / Double(totalSize) : 1.0
            let completed = filesCompleted
            let copied = bytesCopied
            let tSize = totalSize
            let tFiles = totalFiles

            await MainActor.run {
                self.progress = CopyProgress(
                    currentFile: source.lastPathComponent,
                    currentFileProgress: fileProgress,
                    totalProgress: totalProgress,
                    filesCompleted: completed,
                    filesTotal: tFiles,
                    bytesCopied: copied,
                    bytesTotal: tSize
                )
            }
        }

        // 复制文件权限
        try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)

        filesCompleted += 1
    }

    /// 复制目录
    private func copyDirectory(_ source: URL, to destination: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        // 先收集所有文件 URL（避免在 async 上下文中迭代 enumerator）
        var fileURLs: [URL] = []
        if let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) {
            if let items = enumerator.allObjects as? [URL] {
                fileURLs = items
            }
        }

        for itemURL in fileURLs {
            if shouldCancel {
                throw NSError(domain: "FileCopy", code: -1, userInfo: [NSLocalizedDescriptionKey: "用户已取消复制"])
            }

            let relativePath = itemURL.path.replacingOccurrences(of: source.path, with: "")
            let destItemURL = destination.appendingPathComponent(relativePath)

            if let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
                try fileManager.createDirectory(at: destItemURL, withIntermediateDirectories: true)
            } else {
                try await copySingleFile(itemURL, to: destItemURL)
            }
        }
    }

    /// 获取文件大小描述
    static func sizeDescription(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
