import SwiftUI

/// 首次使用引导视图（两步：安装核心组件 + 完全磁盘访问权限）
struct SetupView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject private var comp = ComponentsManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 标题
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    Text("开始使用 NTFS 拷贝助手")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("只需完成以下两步，即可在 Mac 上直接读写 NTFS 硬盘\n全程无需重启电脑")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                // 步骤一：安装核心组件
                stepCard(
                    number: 1,
                    icon: "shippingbox.fill",
                    title: "安装核心组件",
                    description: "内置 NTFS 读写驱动（约 20MB），安装到系统目录，只需一次",
                    status: comp.goNfsv4Status,
                    actionTitle: comp.isInstalling ? nil : "一键安装（需要输入开机密码）"
                ) {
                    Task { await comp.installAll() }
                }

                // 步骤二：完全磁盘访问权限
                stepCard(
                    number: 2,
                    icon: "lock.shield.fill",
                    title: "授权完全磁盘访问权限",
                    description: "macOS 要求：访问硬盘设备必须获得此权限。添加本应用后，请完全退出（⌘Q）并重新打开",
                    status: comp.fdaStatus,
                    actionTitle: "打开系统设置"
                ) {
                    comp.openFDASettings()
                }

                // 完成按钮
                if comp.allComponentsInstalled {
                    Button {
                        viewModel.showSetupView = false
                        viewModel.refreshVolumes()
                    } label: {
                        Label("开始使用", systemImage: "checkmark.circle.fill")
                            .frame(minWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .padding(.top, 8)
                }

                // 安装日志
                if !comp.installLog.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("安装日志")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        ForEach(Array(comp.installLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.contains("✅") ? .green : (line.contains("❌") ? .red : .secondary))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
                    .padding(.horizontal, 40)
                }

                Spacer(minLength: 30)
            }
        }
        .onAppear {
            comp.checkAll()
        }
    }

    // MARK: - 步骤卡片

    private func stepCard(
        number: Int,
        icon: String,
        title: String,
        description: String,
        status: ComponentStatus,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // 步骤编号
                ZStack {
                    Circle()
                        .fill(statusColor(status))
                        .frame(width: 32, height: 32)
                    if status == .installed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if status == .installed {
                    Text("已完成")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }

            if status != .installed, let actionTitle = actionTitle {
                Button(action: action) {
                    if comp.isInstalling && number == 1 {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在安装...")
                        }
                    } else {
                        Text(actionTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(comp.isInstalling)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor(status).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 40)
    }

    private func statusColor(_ status: ComponentStatus) -> Color {
        switch status {
        case .installed: return .green
        case .notInstalled: return .orange
        case .unknown: return .gray
        }
    }
}
