import Foundation

/// 表示一个磁盘卷
struct Volume: Identifiable, Equatable, Hashable {
    let id = UUID()
    /// 卷名称（如 "MyNTFSDrive"）
    let name: String
    /// 挂载点路径（如 "/Volumes/MyNTFSDrive"）
    let mountPoint: String
    /// 设备标识符（如 "disk2s1"）
    let deviceIdentifier: String
    /// 文件系统类型（如 "ntfs", "apfs", "exfat"）
    let fileSystemType: String
    /// 是否可写
    var isWritable: Bool
    /// 总容量（字节）
    let totalSize: Int64
    /// 可用空间（字节）
    let freeSize: Int64

    /// 是否为 NTFS 文件系统
    var isNTFS: Bool {
        fileSystemType.lowercased().contains("ntfs")
    }

    /// 总容量描述
    var totalSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    /// 可用空间描述
    var freeSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: freeSize, countStyle: .file)
    }

    /// 已用空间描述
    var usedSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: totalSize - freeSize, countStyle: .file)
    }

    /// 已用百分比（0-100）
    var usedPercent: Double {
        guard totalSize > 0 else { return 0 }
        return Double(totalSize - freeSize) / Double(totalSize) * 100
    }
}
