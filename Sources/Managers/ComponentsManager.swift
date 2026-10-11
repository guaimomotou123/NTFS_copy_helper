import Foundation
import AppKit
import Combine

/// 核心组件安装状态
enum ComponentStatus {
    case installed      // 已安装
    case notInstalled   // 未安装
    case unknown        // 检测中
}

/// 核心组件管理器
/// 架构说明：应用自带全部 NTFS 读写组件（ntfs-3g + fuse-t 兼容层 + go-nfsv4 NFS 服务），
/// 不依赖 Homebrew / macFUSE / 内核扩展，首次使用仅需一步安装 + 完全磁盘访问权限。
final class ComponentsManager: ObservableObject {
    static let shared = ComponentsManager()

    // MARK: - 发布的状态

    @Published var goNfsv4Status: ComponentStatus = .unknown
    @Published var fdaStatus: ComponentStatus = .unknown
    @Published var isInstalling = false
    @Published var installLog: [String] = []

    var allComponentsInstalled: Bool {
        goNfsv4Status == .installed && fdaStatus == .installed
    }

    // MARK: - 路径

    /// 应用内置组件目录
    static var bundledComponentsDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("ntfs")
    }

    /// ntfs-3g 二进制路径（优先使用应用内置，回退到系统位置）
    static var ntfs3gPath: String? {
        if let bundled = bundledComponentsDir?.appendingPathComponent("ntfs-3g").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ntfs-3g") {
            return "/usr/local/bin/ntfs-3g"
        }
        return nil
    }

    /// ntfsfix 二进制路径
    static var ntfsfixPath: String? {
        if let bundled = bundledComponentsDir?.appendingPathComponent("ntfsfix").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ntfsfix") {
            return "/usr/local/bin/ntfsfix"
        }
        return nil
    }

    // MARK: - 检测

    /// 检查所有组件状态
    func checkAll() {
        // go-nfsv4（NFS 服务端，libfuse-t 硬编码要求位于 /usr/local/bin）
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/go-nfsv4") {
            goNfsv4Status = .installed
        } else if Self.bundledComponentsDir?.appendingPathComponent("go-nfsv4") != nil {
            goNfsv4Status = .notInstalled
        } else {
            goNfsv4Status = .notInstalled
        }

        // 完全磁盘访问权限
        fdaStatus = NTFSManager.shared.hasFullDiskAccess() ? .installed : .notInstalled
    }

    // MARK: - 安装

    /// 一键安装：把内置组件安装到位（一次管理员授权）
    /// 1. go-nfsv4 → /usr/local/bin/（libfuse-t 硬编码路径，必须）
    /// 2. 清除应用包的隔离属性（Quarantine），避免 Gatekeeper 拦截内置二进制
    func installAll() async {
        await MainActor.run {
            isInstalling = true
            installLog.removeAll()
        }

        defer {
            Task { @MainActor in
                self.isInstalling = false
                self.checkAll()
            }
        }

        guard let bundledDir = Self.bundledComponentsDir else {
            await MainActor.run { log("❌ 未找到应用内置组件（Resources/ntfs），安装包可能不完整") }
            return
        }

        await MainActor.run { log("① 正在安装 NTFS 核心组件（约 20MB）...") }

        let bundlePath = Bundle.main.bundlePath
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        mkdir -p /usr/local/bin
        cp -f "\(bundledDir.path)/go-nfsv4" /usr/local/bin/go-nfsv4
        chmod 755 /usr/local/bin/go-nfsv4
        chown root:wheel /usr/local/bin/go-nfsv4
        xattr -cr "\(bundlePath)" 2>/dev/null
        echo INSTALL_DONE
        """

        let result = ShellHelper.shared.runAsAdmin(script)

        await MainActor.run {
            if result.output.contains("INSTALL_DONE") {
                log("✅ 组件安装完成")
            } else {
                log("❌ 安装失败：\(result.error.isEmpty ? result.output : result.error)")
            }
        }
    }

    /// 打开「完全磁盘访问权限」设置页
    func openFDASettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 日志

    @MainActor
    private func log(_ line: String) {
        installLog.append(line)
    }
}
