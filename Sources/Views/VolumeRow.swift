import SwiftUI

/// 卷列表行视图
struct VolumeRow: View {
    let volume: Volume
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // 图标
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 36, height: 36)
                Image(systemName: volumeIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(volume.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if volume.isNTFS {
                        Text("NTFS")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 0)
                }

                // 容量进度条
                VStack(spacing: 2) {
                    ProgressView(value: volume.usedPercent / 100)
                        .progressViewStyle(.linear)
                        .tint(progressColor)
                    HStack {
                        Text("\(volume.usedSizeDescription) 已用")
                        Spacer()
                        Text("\(volume.totalSizeDescription)")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // 读写状态指示
            VStack(spacing: 4) {
                Image(systemName: volume.isWritable ? "pencil" : "eye")
                    .font(.system(size: 14))
                    .foregroundStyle(volume.isWritable ? .green : .orange)
                Text(volume.isWritable ? "可写" : "只读")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private var volumeIcon: String {
        if volume.isNTFS { return "externaldrive.fill" }
        if volume.fileSystemType.lowercased().contains("apfs") { return "internaldrive" }
        if volume.fileSystemType.lowercased().contains("exfat") { return "externaldrive" }
        if volume.fileSystemType.lowercased().contains("fat") { return "externaldrive" }
        return "opticaldiscdrive"
    }

    private var iconBackgroundColor: Color {
        if volume.isNTFS { return .blue }
        if volume.fileSystemType.lowercased().contains("apfs") { return .gray }
        return .purple
    }

    private var progressColor: Color {
        if volume.usedPercent > 90 { return .red }
        if volume.usedPercent > 70 { return .orange }
        return .green
    }
}
