<p align="center">
  <img src="icon.png" width="128" height="128" alt="SoundPin 图标">
</p>

<h1 align="center">SoundPin</h1>

<p align="center">
  让 Mac 始终使用你指定的麦克风和扬声器。<br>
  Keep your Mac on the audio devices you chose.
</p>

<p align="center">
  <a href="https://github.com/realruian/SoundPin/releases/latest"><img src="https://img.shields.io/github/v/release/realruian/SoundPin?style=flat&color=blue" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%26%20Intel)-brightgreen" alt="Universal Architecture">
  <img src="https://img.shields.io/badge/Swift-5-orange?logo=swift" alt="Swift 5">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

<p align="center">
  简体中文 · <a href="README.en.md">English</a>
</p>

<p align="center">
  <img src="screenshot.png" width="364" alt="SoundPin 面板截图">
</p>

---

## 背景

macOS 没有固定音频输入与输出设备的选项。当连接 AirPods 时，系统会自动将麦克风切换至耳机；插入带有音频通道的外接显示器或扩展坞时，默认输出也会被强行切换。

SoundPin（中文名“定音”）为扬声器、耳机和麦克风分别维护一份优先级列表。当设备连接、断开，或系统默认设备被其他应用改动时，自动切回当前可用的最高优先级设备。

## 功能

- **按优先级自动切换**：设备插拔或被外部应用篡改默认设备时，自动切回当前最高优先级设备。
- **耳机与扬声器独立管理**：连接耳机时自动使用耳机，断开后自动恢复桌面扬声器；通过硬件传输协议过滤，HDMI 与 DisplayPort 显示器音频不会被误识别为耳机。
- **点击置顶**：在面板中点击任意设备即可立即选用，并自动置顶为该类别第一优先级。
- **滚轮调节音量**：鼠标悬停在音量滑块上可直接滚动滚轮微调音量。
- **系统风格面板**：依照 macOS 系统声音菜单设计，菜单栏图标跟随音量、静音及耳机状态动态更新。
- **离线设备记忆**：断开连接的设备仍保留在排序列表中并标有最后活跃时间，支持脱机调整优先级。
- **轻量与隐私**：基于 CoreAudio 底层事件监听，无轮询开销；不申请麦克风录音权限，不联网，无任何遥测代码。
- **双语界面**：支持简体中文与英文，默认跟随系统语言，亦可在菜单中手动指定。

## 安装

适用于 Apple Silicon（M1 ~ M4 系列）与 Intel Mac，支持 macOS 13 及更高版本。

### 下载安装包

1. 前往 [Releases](https://github.com/realruian/SoundPin/releases/latest) 下载最新的 `.dmg` 文件。
2. 打开并将 `SoundPin` 拖入应用程序（Applications）文件夹。
3. 首次打开时，若提示开发者无法验证，请前往“系统设置 → 隐私与安全性”，在页面下方点击“仍要打开”。也可以在终端运行以下命令移除隔离标识：
   ```bash
   xattr -dr com.apple.quarantine /Applications/SoundPin.app
   ```

**从 2.1 或更早版本（Audio Priority Bar）升级**：  
2.2 版本起应用更名为 SoundPin（定音）并使用新的 Bundle ID。安装后请将旧版应用删除，你的设备顺序和偏好设置会在首次启动时自动导入，开机自启需在菜单中重新开启一次。

### 从源码构建

需要 Xcode 命令行工具：

```bash
git clone https://github.com/realruian/SoundPin.git
cd SoundPin
./install.sh
```

`install.sh` 会编译 Universal 通用架构二进制文件，安装至 `/Applications/SoundPin.app` 并启动。

## 使用说明

应用启动后常驻在菜单栏，点击喇叭图标展开控制面板：

| 操作 | 效果 |
|---|---|
| 单击设备 | 立即选用该设备，并提升为该分类第一优先级 |
| 拖拽设备 | 调整优先级顺序 |
| 悬停音量条滚动 | 使用鼠标或触控板滚轮快速调节音量 |
| 设备右侧 ⋯ 菜单 | 设置“永不自动选用”、“在列表中忽略”或在耳机/扬声器间手动归类 |
| 面板右上角 ⋯ 菜单 | 开关自动切换、开机启动、编辑设备列表、切换语言、退出 |
| 编辑设备列表 | 显示已断开的离线设备，方便提前排序或删除废弃设备 |
| 声音设置… | 打开系统声音设置 |

关闭“自动切换设备”后，应用停止干预，面板顶部会显示“自动切换已暂停”，点击即可恢复。

## 工作原理

- **事件监听**：调用 CoreAudio 底层 C API（`AudioObjectAddPropertyListenerBlock`）监听全局音频硬件事件，实时响应设备插拔与默认设备变动。
- **持久化绑定**：通过设备硬件唯一 UID 记录优先级，拔掉设备或重启系统后依然生效（偏好设置存储于 `io.github.realruian.SoundPin` 域）。
- **设备识别**：结合设备的传输类型（`kAudioDevicePropertyTransportType`）与内置品牌声学关键词库，区分耳机与扬声器。

查看本地偏好设置：
```bash
defaults read io.github.realruian.SoundPin
```

## 已知限制

- **部分小众品牌蓝牙耳机**：若未命中内置声学关键词，可能初次连接时被分到扬声器组。在设备右侧 ⋯ 菜单选择“移到耳机”即可，选择会被永久记住。
- **隔空播放（AirPlay）**：未主动连接的 AirPlay 设备不会出现在列表中。
- **蓝牙连接**：仅管理已连接至 Mac 的设备，不包含蓝牙扫描与主动配对功能。

## 卸载

在面板 ⋯ 菜单中退出应用，然后在终端中运行：

```bash
rm -rf /Applications/SoundPin.app
defaults delete io.github.realruian.SoundPin
```

## 开发工具

仓库包含以下辅助脚本：

- `tools/render-preview.sh [输出.png] [--demo] [--lang en|zh-Hans]`：利用 SwiftUI 离线渲染面板预览图，无需实际插拔硬件。
- `tools/check-devices.sh`：测试常见音频设备的自动归类与图标匹配规则。
- `tools/make-dmg.sh`：构建 Universal 通用版本并打包生成 DMG。

## 致谢

本项目基于 [tobi/AudioPriorityBar](https://github.com/tobi/AudioPriorityBar) 进行重构与功能演进。2.1 及之前版本沿用原名 Audio Priority Bar，2.2 起更名为 SoundPin（定音）。

相比原版的改进：
- 按 macOS 系统声音控制面板重新设计界面；
- 点击设备直接切换并置顶优先级（原版在自动模式下点击无效）；
- 音量滑块支持滚轮微调；
- 内置中英双语界面，默认跟随系统；
- 菜单栏图标跟随音量大小、静音及耳机型号动态更新；
- 针对 HDMI / DisplayPort 音频输出增加传输通道过滤，防止被误判为耳机；
- 支持离线设备持久记忆、最后活跃时间标注与脱机排序；
- 修复了新版 macOS 菜单栏面板偶发折叠与空白的问题。

## 许可证

[MIT](LICENSE)
