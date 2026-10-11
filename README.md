# NTFS 拷贝助手

在 Mac 上直接读写 NTFS 硬盘的小工具：支持把 Mac 中的文件/文件夹复制到 NTFS 硬盘，也支持把 NTFS 硬盘中的文件复制回 Mac。

应用内置全部读写组件（ntfs-3g + fuse-t 兼容层 + go-nfsv4），**无需安装 Homebrew、无需安装 macFUSE、无需批准内核扩展、无需重启电脑**。

## 功能

- **Mac → NTFS**：一键将 NTFS 卷挂载为读写模式，复制文件或整个文件夹（支持递归）到硬盘
- **NTFS → Mac**：切换复制方向，把硬盘里的文件/文件夹复制到 Mac 任意位置
- 内置读写驱动，开箱即用，不依赖任何第三方软件包管理器
- 通用二进制（Universal），同时支持 **Apple Silicon（M 系列芯片）和 Intel 芯片**
- 实时复制进度、速度统计，支持中途取消
- 自动识别 NTFS 卷，挂载失败时自动尝试修复（ntfsfix）

## 系统要求

- macOS 13.0（Ventura）或更高版本
- Apple Silicon / Intel 芯片均可

## 安装流程（普通用户）

1. 将 `NTFS 拷贝助手.app` 拖到「应用程序」文件夹
2. 双击打开。如果系统提示「无法打开，因为无法验证开发者」（未签名版本），请右键点击应用 → 选择「打开」→ 在弹窗中再点「打开」
3. 首次使用按引导完成两步设置：
   - **安装核心组件**：点击「一键安装」，输入一次 Mac 开机密码（将内置驱动安装到 `/usr/local/bin`，只需一次）
   - **授权完全磁盘访问权限**：点击「打开系统设置」，在「隐私与安全性 → 完全磁盘访问权限」中添加本应用，然后按 `⌘Q` 完全退出并重新打开应用
4. 点击「开始使用」即可

> 「完全磁盘访问权限」是 macOS 的强制要求：任何软件读写外接硬盘的原始设备都必须获得此授权。

## 使用方式

### 把 Mac 的文件复制到 NTFS 硬盘

1. 从左侧硬盘列表选中你的 NTFS 硬盘
2. 若显示「启用写入」按钮，点击它并输入密码（只需一次，之后显示绿色「已可写入」）
3. 将文件或文件夹拖入虚线框，或点击「选择文件或文件夹」按钮添加（可多选、可混选）
4. 点击「开始复制」

### 把 NTFS 硬盘的文件复制到 Mac

1. 将顶部方向切换为「**硬盘 → Mac**」
2. 在「保存位置」一行点击「选择」，指定 Mac 上的目标文件夹（如桌面、下载）
3. 从选中的硬盘中添加文件/文件夹（选择器会默认打开硬盘根目录，也可以直接从 Finder 拖入）
4. 点击「开始复制」

### 其他操作

- **刷新**：插入/拔出硬盘后点击右上角「刷新」更新列表
- **弹出**：复制完成后点击「弹出」安全移除硬盘，避免数据损坏
- **取消复制**：复制过程中点击「取消」，已复制一半的文件会自动清理

## 从源码构建（开发者）

环境要求：Xcode Command Line Tools（`xcode-select --install`）

```bash
./build.sh        # 构建，产物在 build/NTFS 拷贝助手.app
./build.sh run    # 构建并启动
```

构建脚本会自动：

1. 编译 `Sources/` 下的全部 Swift 代码
2. 将 `Resources/ntfs/` 内置组件（约 22MB，通用二进制）打包进 App Bundle
3. 对 App 进行 ad-hoc 代码签名

### 重新编译内置 NTFS 组件

内置组件位于 `Resources/ntfs/`：

| 文件 | 作用 |
|---|---|
| `ntfs-3g` | NTFS 用户态读写驱动 |
| `ntfsfix` | NTFS 卷修复工具 |
| `libntfs-3g.89.dylib` | NTFS 驱动核心库 |
| `libfuse-t.dylib` | fuse-t 用户态 FUSE 兼容层 |
| `go-nfsv4` | 本地 NFS 服务（fuse-t 底层依赖，安装时拷贝到 `/usr/local/bin`） |

交叉编译要点（ntfs-3g 2022.10.3）：

```bash
# 用 libfuse-t 对应架构的 slice 伪造链接库（其 install name 已是 @executable_path/libfuse-t.dylib）
lipo -thin arm64 libfuse-t.dylib -output fakelib/arm/libfuse.dylib
lipo -thin x86_64 libfuse-t.dylib -output fakelib/x86/libfuse.dylib

# 分架构交叉编译（禁用 gettext 以避免 x86-only 的 libintl 依赖）
ac_cv_header_libintl_h=no ./configure \
  --host=arm64-apple-darwin --build=x86_64-apple-darwin \
  CC="clang -arch arm64" CFLAGS="-mmacosx-version-min=13.0" \
  --with-fuse=external CPPFLAGS="-I/usr/local/include" \
  LDFLAGS="-Lfakelib/arm -mmacosx-version-min=13.0"
make -j8

# 改接依赖并合并为通用二进制
install_name_tool -change /tmp/ntfs3g-arm/lib/libntfs-3g.89.dylib \
  @executable_path/libntfs-3g.89.dylib ntfs-3g ntfsfix
install_name_tool -id @executable_path/libntfs-3g.89.dylib libntfs-3g.89.dylib
lipo -create ntfs-3g.x86 ntfs-3g.arm -output ntfs-3g
codesign --force -s - ntfs-3g
```

## 分发说明

当前构建使用 **ad-hoc 签名**，适合本机使用或小范围分发（用户首次打开需右键 → 打开）。

正式对外分发建议：

1. 注册 Apple Developer 账号，使用 **Developer ID** 证书签名
2. 使用 `notarytool` 提交 Apple 公证并 `stapler staple`
3. 公证后的应用用户双击即可打开，无 Gatekeeper 拦截

> 受 App Sandbox 和禁止提权的审核规则限制，读写型 NTFS 工具无法上架 Mac App Store，建议通过 Developer ID + 公证方式分发。

## 卸载

- 删除应用：将 `NTFS 拷贝助手.app` 移到废纸篓
- 删除已安装的核心组件（可选）：在终端执行
  ```bash
  sudo rm -f /usr/local/bin/go-nfsv4
  ```
- 在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中移除本应用（可选）

## 开源许可

ntfs-3g 基于 GPLv2 许可；fuse-t 基于 BSD 许可。
