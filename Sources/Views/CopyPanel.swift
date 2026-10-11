import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 文件复制面板
struct CopyPanel: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题 + 方向切换
            HStack {
                Text(viewModel.copyDirection == .macToNTFS ? "复制文件到 NTFS" : "复制文件到 Mac")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Picker("方向", selection: $viewModel.copyDirection) {
                    Text("Mac → 硬盘").tag(MainViewModel.CopyDirection.macToNTFS)
                    Text("硬盘 → Mac").tag(MainViewModel.CopyDirection.ntfsToMac)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            ScrollView {
                VStack(spacing: 16) {
                    // 目标卷信息
                    destinationSection

                    // 文件拖放区
                    dropZoneSection

                    // 文件列表
                    if !viewModel.sourceFiles.isEmpty {
                        fileListSection
                    }

                    // 操作按钮
                    actionButtons
                }
                .padding()
            }
        }
    }

    // MARK: - 目标卷区域

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.copyDirection == .macToNTFS ? "目标硬盘" : "来源硬盘")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let volume = viewModel.selectedVolume {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 40, height: 40)
                        Image(systemName: "externaldrive.fill")
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(volume.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(volume.mountPoint)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("可用空间：\(volume.freeSizeDescription)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // 写入状态/按钮仅 Mac → 硬盘方向显示
                    if viewModel.copyDirection == .macToNTFS && volume.isNTFS {
                        if volume.isWritable {
                            // 已开启写入：显示绿色完成状态，避免误解为还需点击
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("已可写入")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                        } else {
                            Button {
                                viewModel.mountAsReadWrite()
                            } label: {
                                Label("启用写入", systemImage: "lock.open")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                )

                // 硬盘 → Mac：选择 Mac 上的保存位置
                if viewModel.copyDirection == .ntfsToMac {
                    macDestinationRow
                }
            } else {
                HStack {
                    Image(systemName: "arrow.left")
                        .foregroundStyle(.secondary)
                    Text(viewModel.copyDirection == .macToNTFS ? "请从左侧选择一个 NTFS 硬盘" : "请从左侧选择要读取的硬盘")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.05))
                )
            }
        }
    }

    /// Mac 保存位置选择行（硬盘 → Mac 方向）
    private var macDestinationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.arrow.down")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("保存位置")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(viewModel.macDestinationPath.isEmpty ? "未选择（默认可选桌面、下载等）" : viewModel.macDestinationPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Button("选择") {
                selectMacDestination()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    // MARK: - 拖放区域

    private var dropZoneSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDragging ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isDragging ? Color.blue : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                            )
                    )

                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 36))
                        .foregroundStyle(isDragging ? .blue : .secondary)

                    Text(viewModel.copyDirection == .macToNTFS ? "拖放文件或文件夹到此处" : "拖放硬盘中的文件或文件夹到此处")
                        .font(.subheadline)
                        .foregroundStyle(isDragging ? .blue : .primary)

                    Text("支持任意文件，也可选择整个文件夹")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("选择文件或文件夹") {
                        selectItems()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding(24)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                var urls: [URL] = []
                let group = DispatchGroup()

                for provider in providers {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let data = item as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urls.append(url)
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    viewModel.addSourceFiles(urls)
                }
                return true
            }
        }
    }

    // MARK: - 文件列表

    private var fileListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待复制文件（\(viewModel.sourceFiles.count)）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("总计：\(FileCopyManager.sizeDescription(viewModel.totalSourceSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("清空") {
                    viewModel.clearSourceFiles()
                }
                .font(.caption)
            }

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(viewModel.sourceFiles, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(systemName: fileIcon(for: url))
                                .frame(width: 20)
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                viewModel.removeSourceFile(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.05))
                        )
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if viewModel.isCopying, let progress = viewModel.copyProgress {
                progressView(progress)
            }

            HStack(spacing: 12) {
                if viewModel.isCopying {
                    Button {
                        viewModel.cancelCopy()
                    } label: {
                        Label("取消", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task {
                            await viewModel.startCopy()
                        }
                    } label: {
                        Label("开始复制", systemImage: "arrow.right.doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(startCopyDisabled)

                    if viewModel.selectedVolume != nil {
                        Button {
                            viewModel.ejectVolume()
                        } label: {
                            Label("弹出", systemImage: "eject")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - 进度视图

    private func progressView(_ progress: CopyProgress) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(progress.currentFile)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(progress.totalProgress * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            ProgressView(value: progress.totalProgress)
                .progressViewStyle(.linear)

            HStack {
                Text("文件 \(progress.filesCompleted)/\(progress.filesTotal)")
                Spacer()
                Text("\(FileCopyManager.sizeDescription(progress.bytesCopied)) / \(FileCopyManager.sizeDescription(progress.bytesTotal))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.08))
        )
    }

    // MARK: - 辅助方法

    /// 开始复制按钮的禁用条件（按方向检查必要条件）
    private var startCopyDisabled: Bool {
        if viewModel.sourceFiles.isEmpty { return true }
        switch viewModel.copyDirection {
        case .macToNTFS:
            return viewModel.selectedVolume == nil
        case .ntfsToMac:
            return viewModel.macDestinationPath.isEmpty
        }
    }

    /// 弹出选择器（可同时多选文件和文件夹）
    private func selectItems() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "选择"
        // 硬盘 → Mac 方向默认打开选中的硬盘
        if viewModel.copyDirection == .ntfsToMac, let mp = viewModel.selectedVolume?.mountPoint {
            panel.directoryURL = URL(fileURLWithPath: mp)
        }
        panel.message = "选择要复制的文件或文件夹"
        if panel.runModal() == .OK {
            viewModel.addSourceFiles(panel.urls)
        }
    }

    /// 选择 Mac 上的保存位置（硬盘 → Mac 方向）
    private func selectMacDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择文件保存到 Mac 的哪个文件夹"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.macDestinationPath = url.path
        }
    }

    private func fileIcon(for url: URL) -> String {
        // 文件夹
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return "folder.fill"
        }
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "avi", "mkv", "flv", "wmv", "m4v"].contains(ext) {
            return "film"
        }
        if ["mp3", "wav", "flac", "aac", "ogg", "m4a", "wma"].contains(ext) {
            return "music.note"
        }
        if ["jpg", "jpeg", "png", "gif", "bmp", "heic", "tiff"].contains(ext) {
            return "photo"
        }
        if ["zip", "rar", "7z", "tar", "gz"].contains(ext) {
            return "doc.zipper"
        }
        if ["pdf", "doc", "docx", "txt", "rtf"].contains(ext) {
            return "doc.text"
        }
        return "doc"
    }
}
