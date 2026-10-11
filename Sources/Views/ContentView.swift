import SwiftUI

/// 主内容视图
struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            headerView

            Divider()

            if viewModel.showSetupView {
                SetupView(viewModel: viewModel)
            } else {
                mainContentView
            }

            // 底部状态栏
            statusBar
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("需要完全磁盘访问权限", isPresented: $viewModel.showFDAError) {
            Button("打开系统设置") {
                viewModel.openFullDiskAccessSettings()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("macOS 要求：访问 NTFS 硬盘的原始设备必须拥有「完全磁盘访问权限」。\n\n操作步骤：\n1. 在打开的设置页中找到「完全磁盘访问权限」\n2. 点击「+」添加「NTFS 拷贝助手」App\n3. 完全退出本应用（⌘Q）后重新打开")
        }
        .onAppear {
            viewModel.checkDependencies()
            viewModel.refreshVolumes()
        }
    }

    // MARK: - 顶部标题栏

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill.badge.plus")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("NTFS 拷贝助手")
                    .font(.headline)
                Text("将视频、音频和文件复制到 NTFS 硬盘")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.checkDependencies()
            } label: {
                Label("检查依赖", systemImage: "wrench.and.screwdriver")
            }

            Button {
                viewModel.refreshVolumes()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - 主内容区

    private var mainContentView: some View {
        HSplitView {
            // 左侧：卷列表
            volumeListView
                .frame(minWidth: 280, maxWidth: 360)

            // 右侧：复制面板
            CopyPanel(viewModel: viewModel)
                .frame(minWidth: 400)
        }
    }

    // MARK: - 卷列表

    private var volumeListView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("硬盘列表")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            List(selection: $viewModel.selectedVolume) {
                ForEach(viewModel.volumes) { volume in
                    VolumeRow(volume: volume, isSelected: viewModel.selectedVolume == volume)
                        .tag(volume)
                        .onTapGesture {
                            viewModel.selectedVolume = volume
                            viewModel.destinationPath = volume.mountPoint
                        }
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(viewModel.statusMessage)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var statusIcon: String {
        switch viewModel.statusType {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var statusColor: Color {
        switch viewModel.statusType {
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
