import Foundation

/// Shell 命令执行结果
struct ShellResult {
    let output: String
    let error: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    /// 合并的完整输出（stdout + stderr）
    var combinedOutput: String {
        [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// 执行 Shell 命令的工具类
final class ShellHelper {
    static let shared = ShellHelper()
    private init() {}

    /// 包含 Homebrew 路径的完整 PATH（GUI 启动的 App 默认 PATH 不含 /usr/local/bin）
    private static let fullPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// 执行普通命令（无需管理员权限）
    /// - Parameters:
    ///   - command: 可执行文件路径
    ///   - arguments: 参数
    ///   - mergeOutput: 是否将 stderr 合并到 stdout
    @discardableResult
    func run(_ command: String, arguments: [String] = [], mergeOutput: Bool = false) -> ShellResult {
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: command)
        task.arguments = arguments
        task.standardOutput = outputPipe
        task.standardError = mergeOutput ? outputPipe : errorPipe
        task.standardInput = Pipe()

        // 设置完整的环境变量
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ShellHelper.fullPath
        env["HOME"] = NSHomeDirectory()
        task.environment = env

        do {
            try task.run()
        } catch {
            return ShellResult(output: "", error: error.localizedDescription, exitCode: -1)
        }

        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = mergeOutput ? Data() : errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ShellResult(output: output, error: err, exitCode: task.terminationStatus)
    }

    /// 执行 bash 脚本（自动注入包含 Homebrew 的 PATH）
    @discardableResult
    func runBash(_ script: String, mergeOutput: Bool = true) -> ShellResult {
        return run("/bin/bash", arguments: ["-c", script], mergeOutput: mergeOutput)
    }

    /// 以登录 shell 执行（加载用户 profile 环境）
    @discardableResult
    func runLoginBash(_ script: String, mergeOutput: Bool = true) -> ShellResult {
        return run("/bin/bash", arguments: ["-l", "-c", script], mergeOutput: mergeOutput)
    }

    /// 执行需要管理员权限的命令（通过 AppleScript 弹出授权窗口）
    /// 每次调用只弹出一次密码授权窗口
    /// 注意：Homebrew 命令绝不能使用此方法，必须以普通用户运行
    @discardableResult
    func runAsAdmin(_ command: String) -> ShellResult {
        // 将脚本写入临时文件执行，避免 AppleScript 字符串的转义/换行限制，
        // 同时保证多行复杂脚本（if/for 等）可以原样运行
        let tempScript = "/tmp/.ntfs_admin_\(UUID().uuidString.prefix(8)).sh"
        let script = "#!/bin/bash\nexport PATH=\(ShellHelper.fullPath)\n\(command)\n"

        do {
            try script.write(toFile: tempScript, atomically: true, encoding: .utf8)
            _ = try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: tempScript)
        } catch {
            return ShellResult(output: "", error: "无法写入临时脚本: \(error.localizedDescription)", exitCode: -1)
        }

        // 一条 do shell script 完成执行+清理，整个流程只触发一次授权
        let innerCommand = "/bin/bash \(tempScript) 2>&1; __RC=$?; rm -f \(tempScript); exit $__RC"
        let appleScript = "do shell script \"\(innerCommand)\" with administrator privileges"

        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", appleScript]
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        task.standardInput = Pipe()

        do {
            try task.run()
        } catch {
            try? FileManager.default.removeItem(atPath: tempScript)
            return ShellResult(output: "", error: error.localizedDescription, exitCode: -1)
        }

        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ShellResult(output: output, error: err, exitCode: task.terminationStatus)
    }
}
