import Foundation

/// 负责检测 NTFS 硬盘并以读写模式重新挂载
final class NTFSManager {
    static let shared = NTFSManager()
    private init() {}

    /// 获取所有已挂载的卷
    func getAllVolumes() -> [Volume] {
        var volumes: [Volume] = []

        // 使用 volumeURLsForDirectory 获取已挂载的卷
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsReadOnlyKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }

        for url in urls {
            guard let resources = try? url.resourceValues(forKeys: Set(keys)) else { continue }

            let name = resources.volumeName ?? url.lastPathComponent
            let isReadOnly = resources.volumeIsReadOnly ?? true
            let totalSize = Int64(resources.volumeTotalCapacity ?? 0)
            let freeSize = Int64(resources.volumeAvailableCapacity ?? 0)

            // 通过 diskutil 获取更详细的文件系统信息和设备标识符
            let (fsType, deviceId) = getFileSystemInfo(for: url.path)

            let volume = Volume(
                name: name,
                mountPoint: url.path,
                deviceIdentifier: deviceId,
                fileSystemType: fsType,
                isWritable: !isReadOnly,
                totalSize: totalSize,
                freeSize: freeSize
            )
            volumes.append(volume)
        }

        return volumes
    }

    /// 获取指定路径的文件系统类型和设备标识符
    private func getFileSystemInfo(for path: String) -> (fileSystem: String, deviceIdentifier: String) {
        let result = ShellHelper.shared.runBash("diskutil info \"\(path)\" 2>/dev/null")
        var fsType = ""
        var deviceId = ""

        for line in result.output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("File System Personality") || trimmed.contains("Type (Bundle)") {
                if let range = trimmed.range(of: ":") {
                    fsType = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
                }
            }
            if trimmed.contains("Device Identifier") {
                if let range = trimmed.range(of: ":") {
                    deviceId = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return (fsType, deviceId)
    }

    /// 检查本应用是否拥有「完全磁盘访问权限」
    /// macOS 10.15+ 访问 /dev/disk* 原始设备必须拥有 FDA，root 也无法绕过
    func hasFullDiskAccess() -> Bool {
        // 探测已知受 TCC 保护的用户文件：能打开 = 有 FDA
        let candidates = [
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
            NSHomeDirectory() + "/Library/Safari/History.db",
            NSHomeDirectory() + "/Library/Messages/chat.db"
        ]
        var probedAny = false
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            probedAny = true
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
        }
        // 找不到任何探测文件时视为通过（不阻塞用户，实际挂载时还有兜底报错）
        return !probedAny
    }

    /// 将 NTFS 卷以读写模式重新挂载
    /// 架构：ntfs-3g（应用内置，已接入 fuse-t 兼容层）→ go-nfsv4 NFS 服务 → 用户态读写
    /// 无需 macFUSE / 内核扩展 / Homebrew；访问原始设备需要应用拥有「完全磁盘访问权限」
    func mountNTFSAsReadWrite(_ volume: Volume) -> (success: Bool, message: String) {
        guard volume.isNTFS else {
            return (false, "该卷不是 NTFS 文件系统")
        }

        guard let ntfs3gPath = ComponentsManager.ntfs3gPath else {
            return (false, "未找到 ntfs-3g，请先在引导页安装核心组件")
        }

        guard FileManager.default.isExecutableFile(atPath: "/usr/local/bin/go-nfsv4") else {
            return (false, "核心组件尚未安装，请先在引导页完成安装")
        }

        guard hasFullDiskAccess() else {
            return (false, "NEEDS_FULL_DISK_ACCESS")
        }

        let devicePath = "/dev/\(volume.deviceIdentifier)"
        let mountPoint = volume.mountPoint

        // 3. 所有操作合并为一条管理员脚本 —— 只弹出一次密码授权窗口
        // 流程：卸载只读挂载 → 建挂载点 → ntfs-3g 读写挂载
        //       → 若失败（脏位）先 ntfsfix 再重试 → 若仍失败回退只读挂载
        let uid = getuid()
        let gid = getgid()
        let mountOpts = "local,noappledouble,volname=\"\(volume.name)\",uid=\(uid),gid=\(gid)"

        let script = """
        diskutil unmount force "\(mountPoint)" >/dev/null 2>&1
        mkdir -p "\(mountPoint)"
        echo "MOUNT1_BEGIN"
        "\(ntfs3gPath)" "\(devicePath)" "\(mountPoint)" -o \(mountOpts) 2>&1
        RC1=$?
        echo "MOUNT1_EXIT:$RC1"
        if [ "$RC1" != "0" ]; then
          echo "NTFSFIX_BEGIN"
          "\(ComponentsManager.ntfsfixPath ?? "/usr/local/bin/ntfsfix")" -d "\(devicePath)" 2>&1
          echo "MOUNT2_BEGIN"
          "\(ntfs3gPath)" "\(devicePath)" "\(mountPoint)" -o \(mountOpts) 2>&1
          RC2=$?
          echo "MOUNT2_EXIT:$RC2"
          if [ "$RC2" != "0" ]; then
            diskutil mount "\(devicePath)" >/dev/null 2>&1
          fi
        fi
        """

        let result = ShellHelper.shared.runAsAdmin(script)
        let output = result.combinedOutput

        // 4. 解析结果（一次授权 → 全部步骤完成）
        let mount1Ok = output.contains("MOUNT1_EXIT:0")
        let mount2Ok = output.contains("MOUNT2_EXIT:0")

        if mount1Ok || mount2Ok {
            return (true, "已成功将「\(volume.name)」以读写模式挂载")
        }

        // 提取挂载阶段的真实错误输出（BEGIN 与 EXIT 标记之间）
        var errText = ""
        if let range1 = output.range(of: "MOUNT1_BEGIN\n"),
           let range2 = output.range(of: "MOUNT1_EXIT:") {
            errText = String(output[range1.upperBound..<range2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if errText.isEmpty, let range1 = output.range(of: "MOUNT2_BEGIN\n"),
           let range2 = output.range(of: "MOUNT2_EXIT:") {
            errText = String(output[range1.upperBound..<range2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if errText.isEmpty {
            errText = result.error.isEmpty ? output : result.error
        }

        // 用户取消了密码授权
        if output.contains("User canceled") || output.contains("-128") {
            return (false, "已取消操作")
        }

        if errText.contains("not permitted") {
            return (false, "NEEDS_FULL_DISK_ACCESS")
        }
        return (false, "挂载失败：\(errText)")
    }

    /// 检查指定卷是否当前为可写状态
    func isVolumeWritable(_ volume: Volume) -> Bool {
        let result = ShellHelper.shared.runBash("mount | grep \"\(volume.mountPoint)\"")
        // ntfs-3g + fuse-t 挂载显示为 nfs 类型（fuse-t:/xxx）
        if result.output.contains("fuse-t:") {
            return !result.output.contains("ro,")
        }
        // 传统 fusefs（macFUSE）挂载
        if result.output.contains("fusefs") {
            return !result.output.contains("ro,")
        }
        if result.output.contains("ntfs") {
            if result.output.contains("rw,") || result.output.contains("read-write") {
                return true
            }
        }
        // 对于非 NTFS 卷，直接用原始属性
        return volume.isWritable
    }

    /// 弹出卷
    func ejectVolume(_ volume: Volume) -> (success: Bool, message: String) {
        let result = ShellHelper.shared.runAsAdmin("diskutil eject \"\(volume.deviceIdentifier)\"")
        if result.exitCode == 0 {
            return (true, "已安全弹出「\(volume.name)」")
        }
        return (false, "弹出失败：\(result.error)")
    }
}
