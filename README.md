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
- **点击置顶**：在面板中点击任意设备即可立即选用；自动切换开启时，还会将其置顶为该类别第一优先级。
- **滚轮调节音量**：鼠标悬停在音量滑块上可直接滚动滚轮微调音量。
- **AirPods 听音模式（实验性）**：设备支持时，展开右侧箭头即可切换通透、自适应和降噪；只显示设备报告支持的模式，不改变输出设备或优先级。
- **蓝牙电量**：设备行显示 macOS 报告的耳机电量，悬停查看左右耳和充电盒明细；两耳不同时显示较低值。仅匹配蓝牙地址可核对的已连接设备，系统不报告时不显示。面板打开时最多每分钟读取一次，充电盒数据可能延迟。
- **系统风格面板**：依照 macOS 系统声音菜单设计，菜单栏图标跟随音量、静音及耳机状态动态更新。
- **离线设备记忆**：断开连接的设备仍保留在排序列表中并标有最后活跃时间，支持脱机调整优先级。
- **轻量与隐私**：基于 CoreAudio 底层事件监听，无持续轮询；不申请麦克风录音权限，不联网，无任何遥测代码。
- **键盘与旁白支持**：完整支持 VoiceOver 旁白读屏与状态播报；支持通过 Tab 键聚焦与空格/回车选用设备（需 macOS 14+ 开启系统“键盘导航”）。
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

需要 Xcode 26 或更高版本（应用图标为 Icon Composer 格式，仅安装命令行工具无法构建）：

```bash
git clone https://github.com/realruian/SoundPin.git
cd SoundPin
./install.sh
```

`install.sh` 会编译适用于本机架构的版本，安装至 `/Applications/SoundPin.app` 并启动。Universal 通用版本由 `tools/make-dmg.sh` 构建。

## 使用说明

应用启动后常驻在菜单栏，点击喇叭图标展开控制面板：

| 操作 | 效果 |
|---|---|
| 单击设备 | 立即选用该设备；自动切换开启时，同时提升为该分类第一优先级 |
| 拖拽设备 | 调整优先级顺序 |
| 悬停音量条滚动 | 使用鼠标或触控板滚轮快速调节音量 |
| 键盘导航（macOS 14+） | 开启系统“键盘导航”后，按 Tab 聚焦设备，空格或回车选用 |
| 设备行右键菜单 | 设置“永不自动选用”、“在列表中忽略”或在耳机/扬声器间手动归类 |
| AirPods 右侧展开箭头 | 展开或收起“听音模式”；单击模式切换 |
| 面板右上角 ⋯ 菜单 | 开关自动切换、开机启动、编辑设备列表、切换语言、退出 |
| 编辑设备列表 | 显示已断开的离线设备，方便提前排序或删除废弃设备 |
| 声音设置… | 打开系统声音设置 |

关闭“自动切换设备”后，应用停止干预，并取消尚未完成的切换重试。面板顶部会显示“自动切换已暂停”，点击即可恢复。

设备列表暂时读取失败时，保留原列表并暂停自动选择，最多安排两次读取重试。手动选择在系统默认设备回读确认后才置顶；切换失败最多追加两次尝试，随后显示重试入口。系统默认设备回读不代表声音播放或耳机听感已经验证。

拖拽和旁白排序操作按设备身份确认目标；拖拽期间列表顺序、连接状态或分类改变时，本次拖拽取消。在列表中隐藏设备不会隐藏当前输出的音量、静音状态或菜单栏耳机图标。音量写入后回读实际值，失败时恢复滑块；仅在写入确认后，才尝试取消原输出设备的静音。

听音模式切换会显示“切换中”，等待系统回读所选模式；约 3.7 秒仍未读到时提示重试，不自动重复写入。断连或设备身份变化会取消待完成请求，重连不重放旧操作。临时读取或监听注册失败最多安排三次恢复；已有入口会保留，但读取失败时清除旧勾选并禁用切换。回读仅表示系统缓存状态，不代表耳机听感确认。

## 工作原理

- **事件监听**：调用 CoreAudio 底层 C API（`AudioObjectAddPropertyListenerBlock`）监听全局音频硬件事件，实时响应设备插拔与默认设备变动。
- **持久化绑定**：通过设备硬件唯一 UID 记录优先级，拔掉设备或重启系统后依然生效（偏好设置存储于 `io.github.realruian.SoundPin` 域）。
- **设备识别**：结合设备的传输类型（`kAudioDevicePropertyTransportType`）与内置品牌声学关键词库，区分耳机与扬声器。

查看本地偏好设置：
```bash
defaults read io.github.realruian.SoundPin
```

## 已知限制

- **听音模式为实验性功能**：使用未公开的 Core Audio HAL 属性，运行时检查支持情况；仅在本机 AirPods Pro 3 已连接但非默认输出时完成听感验证。当前默认输出场景的独立测试因路由中途变化而中断，尚未完成验证。勾选状态来自系统缓存，不代表耳机硬件确认。

- **部分小众品牌蓝牙耳机**：若未命中内置声学关键词，可能初次连接时被分到扬声器组。在设备行右键菜单选择“移到耳机”即可，选择会被永久记住。
- **隔空播放（AirPlay）**：未主动连接的 AirPlay 设备不会出现在列表中。
- **蓝牙连接**：仅管理已连接至 Mac 的设备，不包含蓝牙扫描与主动配对功能。

## 卸载

如已开启“开机启动”，先在面板 ⋯ 菜单中将其关闭，否则“系统设置 → 通用 → 登录项”中会留下一条记录。随后在 ⋯ 菜单中退出应用，并在终端中运行：

```bash
rm -rf /Applications/SoundPin.app
defaults delete io.github.realruian.SoundPin
```

从 Audio Priority Bar 升级而来的用户，旧版的偏好设置可一并删除：

```bash
defaults delete app.audioprioritybar
```

## 开发工具

仓库包含以下辅助脚本：

- `tools/render-preview.sh [输出.png] [--demo] [--lang en|zh-Hans]`：使用模拟设备与内存偏好，通过 SwiftUI 离线渲染预览图；不连接真实音频服务、不读取正式设备排序。`--demo` 添加展示边框；`--listening-state ready|pending|failed|unavailable` 渲染独立的听音模式示例。
- `tools/check-battery.sh [--live]`：检查电量报告解析、地址匹配、缓存与断连保护、读取超时；`--live` 额外只读验证本机蓝牙报告。预览加 `--battery` 可显示模拟电量。
- `tools/check-routing.sh`：使用模拟音频服务和虚拟时钟，检查读取失败、有限重试、暂停取消、手动选择确认与输入／输出端独立连接；不操作真实设备。
- `tools/check-interactions.sh`：使用模拟设备检查拖拽身份校验、列表变化取消、隐藏设备状态、音量写入失败回读与输出中途变化保护；不操作真实设备。
- `tools/check-devices.sh`：测试常见音频设备的自动归类与图标匹配规则。
- `tools/check-listening-modes.sh`：检查听音模式支持位、未知值、无效设备保护，以及模拟硬件上的部分监听注册失败、恢复和清理；不向真实设备写入模式。
- `tools/check-listening-mode-requests.sh`：通过内存服务与虚拟时钟检查待完成请求、超时、重试、断连取消、迟到通知和有限恢复；不链接真实听音模式服务。
- `tools/check-listening-mode-motion.sh`：在独立的真实 MenuBarExtra 中检查展开收起的连续高度、固定锚点、快速反向操作和“减少动态效果”，不创建音频服务。
- `tools/check-settings.sh`：检查设备记忆与“永不自动选用”的存取逻辑，使用内存偏好存储，不写入任何偏好设置域。
- `tools/check-events.sh`：检查连续的设备变化通知是否被合并处理，使用仅本进程可见的测试设备。
- `tools/check-listening-mode-accessibility.sh`：在隔离窗口中通过辅助功能 API 检查听音模式默认操作、等待状态、超时与重试；仅使用模拟设备，需要辅助功能权限。
- `tools/check-panel-acceptance.sh [--reduce-motion] [--record]`：在真实菜单栏面板中检查动画、辅助功能操作和模拟请求；需要辅助功能权限，录制还需要屏幕录制权限。测试时需保持桌面空闲，菜单被关闭或其他菜单栏项目移动会使检查失败；不作为无人值守 CI 检查。
- `tools/check-voiceover.sh [--lang en|zh-Hans]`：不开启旁白，直接读取面板的辅助功能信息并执行一次设备行操作（终端需要“辅助功能”权限）。
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
- 完整支持 VoiceOver 旁白与键盘导航；
- 修复了新版 macOS 菜单栏面板偶发折叠与空白的问题。

## 许可证

[MIT](LICENSE)
