import Foundation
import SwiftUI

/// 主视图模型
@MainActor
final class MainViewModel: ObservableObject {
    @Published var volumes: [Volume] = []
    @Published var selectedVolume: Volume?
    @Published var isLoading = false
    @Published var statusMessage: String = ""
    @Published var statusType: StatusType = .info

    @Published var sourceFiles: [URL] = []
    @Published var destinationPath: String = ""
    @Published var isCopying = false
    @Published var copyProgress: CopyProgress?

    /// 复制方向
    enum CopyDirection {
        case macToNTFS   // Mac → 硬盘
        case ntfsToMac   // 硬盘 → Mac
    }

    @Published var copyDirection: CopyDirection = .macToNTFS
    /// 硬盘 → Mac 时的保存位置
    @Published var macDestinationPath: String = ""

    @Published var showSetupView = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showFDAError = false

    let ntfsManager = NTFSManager.shared
    let copyManager = FileCopyManager.shared
    let componentsManager = ComponentsManager.shared

    enum StatusType {
        case info, success, error, warning
    }

    init() {
        // 监听复制进度
        copyManager.$progress
            .receive(on: DispatchQueue.main)
            .assign(to: &$copyProgress)
        copyManager.$isCopying
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCopying)
    }

    /// 刷新卷列表
    func refreshVolumes() {
        isLoading = true
        volumes = ntfsManager.getAllVolumes()
        isLoading = false

        // 同步选中卷：刷新后卷对象已更新，重新指向新对象以获取最新的读写状态
        if let selected = selectedVolume,
           let updated = volumes.first(where: {
               $0.deviceIdentifier == selected.deviceIdentifier
                   || $0.mountPoint == selected.mountPoint
           }) {
            selectedVolume = updated
        } else if let selected = selectedVolume, !volumes.contains(where: { $0.deviceIdentifier == selected.deviceIdentifier }) {
            selectedVolume = nil
        }

        if volumes.isEmpty {
            setStatus("未检测到已挂载的卷，请连接硬盘后点击刷新", .warning)
        } else {
            let ntfsCount = volumes.filter { $0.isNTFS }.count
            setStatus("检测到 \(volumes.count) 个卷，其中 \(ntfsCount) 个 NTFS 卷", .info)
        }
    }

    /// 挂载选中的 NTFS 卷为读写模式
    func mountAsReadWrite() {
        guard let volume = selectedVolume else {
            setStatus("请先选择一个 NTFS 卷", .warning)
            return
        }
        guard volume.isNTFS else {
            setStatus("选中的卷不是 NTFS 文件系统", .error)
            return
        }

        // 检查组件
        componentsManager.checkAll()
        if !componentsManager.allComponentsInstalled {
            showSetupView = true
            return
        }

        isLoading = true
        let result = ntfsManager.mountNTFSAsReadWrite(volume)
        isLoading = false

        if result.success {
            setStatus(result.message, .success)
            // 刷新卷列表
            refreshVolumes()
        } else if result.message == "NEEDS_FULL_DISK_ACCESS" {
            showFDAError = true
            setStatus("需要「完全磁盘访问权限」才能读写 NTFS 硬盘", .error)
        } else {
            showError(message: result.message)
        }
    }

    /// 打开「完全磁盘访问权限」设置页
    func openFullDiskAccessSettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let u = URL(string: url) {
            NSWorkspace.shared.open(u)
        }
    }

    /// 检查组件
    func checkDependencies() {
        componentsManager.checkAll()
        if !componentsManager.allComponentsInstalled {
            showSetupView = true
        } else {
            setStatus("所有组件已就绪", .success)
        }
    }

    /// 添加源文件
    func addSourceFiles(_ urls: [URL]) {
        for url in urls {
            if !sourceFiles.contains(url) {
                sourceFiles.append(url)
            }
        }
        updateDestinationIfNeeded()
    }

    /// 移除源文件
    func removeSourceFile(_ url: URL) {
        sourceFiles.removeAll { $0 == url }
    }

    /// 清空源文件列表
    func clearSourceFiles() {
        sourceFiles.removeAll()
    }

    /// 设置目标卷
    func setDestinationVolume(_ volume: Volume) {
        selectedVolume = volume
        destinationPath = volume.mountPoint
    }

    /// 如果有选中的卷，自动更新目标路径
    private func updateDestinationIfNeeded() {
        if destinationPath.isEmpty, let volume = selectedVolume {
            destinationPath = volume.mountPoint
        }
    }

    /// 获取源文件总大小
    var totalSourceSize: Int64 {
        copyManager.calculateSize(of: sourceFiles).totalSize
    }

    /// 开始复制（按当前方向）
    func startCopy() async {
        guard !sourceFiles.isEmpty else {
            showError(message: "请先选择要复制的文件")
            return
        }

        switch copyDirection {
        case .macToNTFS:
            guard let volume = selectedVolume else {
                showError(message: "请先选择目标 NTFS 硬盘")
                return
            }
            guard volume.isWritable || ntfsManager.isVolumeWritable(volume) else {
                showError(message: "目标卷是只读状态，请先将其挂载为读写模式")
                return
            }
            let destURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
            await performCopy(to: destURL, destinationName: volume.name)

        case .ntfsToMac:
            guard !macDestinationPath.isEmpty else {
                showError(message: "请先选择 Mac 上的保存位置")
                return
            }
            let destURL = URL(fileURLWithPath: macDestinationPath, isDirectory: true)
            await performCopy(to: destURL, destinationName: "Mac")
        }
    }

    /// 执行复制
    private func performCopy(to destURL: URL, destinationName: String) async {
        do {
            setStatus("开始复制文件...", .info)
            let success = try await copyManager.copyFiles(sourceFiles, to: destURL)
            if success {
                setStatus("复制完成！共复制 \(sourceFiles.count) 个项目到「\(destinationName)」", .success)
                clearSourceFiles()
                refreshVolumes()
            }
        } catch {
            showError(message: "复制失败：\(error.localizedDescription)")
        }
    }

    /// 取消复制
    func cancelCopy() {
        copyManager.cancel()
        setStatus("正在取消复制...", .warning)
    }

    /// 弹出卷
    func ejectVolume() {
        guard let volume = selectedVolume else { return }
        let result = ntfsManager.ejectVolume(volume)
        if result.success {
            setStatus(result.message, .success)
            selectedVolume = nil
            refreshVolumes()
        } else {
            showError(message: result.message)
        }
    }

    // MARK: - 辅助方法

    private func setStatus(_ message: String, _ type: StatusType) {
        statusMessage = message
        statusType = type
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
        setStatus(message, .error)
    }
}
