<p align="center">
  <img src="icon.png" width="128" height="128" alt="SoundPin 图标">
</p>

<h1 align="center">定音 SoundPin</h1>

<p align="center">
  <b>让 Mac 始终使用你指定的麦克风和扬声器，不再被 AirPods 或外接屏幕强行抢走。</b><br>
  A smart audio priority manager for macOS menu bar.
</p>

<p align="center">
  <a href="https://github.com/realruian/SoundPin/releases/latest"><img src="https://img.shields.io/github/v/release/realruian/SoundPin?style=flat&color=blue" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%26%20Intel)-brightgreen" alt="Universal Architecture">
  <img src="https://img.shields.io/badge/Swift-5-orange?logo=swift" alt="Swift 5">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

<p align="center">
  <b>简体中文</b> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <img src="screenshot.png" width="364" alt="SoundPin 面板截图">
</p>

---

## 💡 为什么需要它？

macOS 原生没有“锁定输入/输出设备”或“设备优先级”机制。在日常使用中，你大概率遇到过这些令人抓狂的场景：

- 🎙️ **会议与录音翻车**：桌上明明连着高品质的专业 USB 或声卡麦克风，一旦戴上 AirPods，macOS 就会强行把麦克风切到耳机上，通话音质瞬间变为干瘪的单声道蓝牙通话音质；
- 🔇 **外接设备抢输出**：插上带音频通道的显示器（HDMI / DisplayPort）或雷雳扩展坞时，声音被系统自动引流到根本不出声的显示器喇叭上；
- 🔄 **频繁手动切回**：拔掉耳机后，系统选用的输出设备经常不是你想要的桌面音箱，每次都得点开控制中心反复确认。

**定音（SoundPin）** 彻底终结了这个烦恼：它为**扬声器、耳机和麦克风**各自建立一条清晰的**优先级队列**。只要排名更高的设备在线，哪怕系统或其他 App 试图抢占，它都会毫秒级**自动切回**。

---

## ✨ 核心特性

- 🎯 **优先级智能守门**：按你设定的顺序选用当前在线的最高优先级设备；一旦被系统或第三方软件篡改，**立刻切回**。
- 🎧 **耳机 / 扬声器智能双轨**：
  - 戴上耳机，无缝走耳机输出；
  - 摘掉耳机，平滑切回你的桌面音箱；
  - 结合底层传输通道与声学品牌库识别，**显示器音频绝不误判为耳机**。
- 👆 **即点即顶（Click to Promote）**：在面板中点击任意在线设备不仅立即切换，还会**自动将其置顶**为该分类的第一优先级。
- 🎨 **macOS 原生设计美学**：严格遵循 macOS 设计规范，界面贴合系统“声音”菜单质感；菜单栏图标动态联动（静音、音量大小及当前耳机型号）。
- 🛡️ **纯粹安全，尊重隐私**：
  - **零录音权限**：完全不需要麦克风录音权限；
  - **零网络请求**：不联网、无统计埋点、无远程上报；
  - **极低功耗**：基于 CoreAudio 硬件事件监听驱动，无轮询循环。
- 🌐 **双语界面**：开箱即用支持简体中文与英文，默认跟随系统语言，亦可在菜单中手动指定。

---

## 🚀 安装

适用于所有 Apple Silicon（M1 ~ M4 系列）与 Intel Mac，支持 macOS 13 及更高版本。

### 方式一：直接下载安装包（推荐）

1. 前往 [Releases](https://github.com/realruian/SoundPin/releases/latest) 下载最新的 `.dmg` 安装包；
2. 双击打开，将 `SoundPin` 拖入 **Applications**（应用程序）文件夹；
3. 首次打开时，若提示开发者未验证（应用尚未购买苹果商业公证），请前往「系统设置 → 隐私与安全性」页面底部点击**“仍要打开”**。

> 💡 你也可以在终端直接执行一条命令移除隔离标识：
> ```bash
> xattr -dr com.apple.quarantine /Applications/SoundPin.app
> ```

> 🔁 **从 2.1 或更早版本升级**：那时它叫 Audio Priority Bar（2.2 起改名）。装好后请把"应用程序"里旧的 `AudioPriorityBar` 删掉。原来的设备顺序和设置会自动带过来，"开机启动"需要在新版里重新打开一次。

### 方式二：从源码构建

本地需要安装 Xcode 命令行工具：

```bash
git clone https://github.com/realruian/SoundPin.git
cd SoundPin
./install.sh
```

`install.sh` 会自动构建 Universal 通用二进制文件，安装至 `/Applications/SoundPin.app` 并直接启动。

---

## 📖 使用技巧

应用启动后驻留在顶部菜单栏，点击喇叭图标即可展开面板：

| 操作 | 效果 |
|---|---|
| **单击设备** | 立即切换到该设备，并**将其提升为该分类的第一优先级** |
| **拖拽设备** | 自由调整优先级次序（越靠上优先级越高） |
| **设备右侧 ⋯ 菜单** | 设置“永不自动选用”、“在列表中忽略”或在“耳机 / 扬声器”分类间手动移动 |
| **面板标题右侧 ⋯ 菜单** | 开启/关闭自动切换、开启开机自启、编辑设备列表、切换界面语言、退出 |
| **编辑设备列表** | 展开所有历史/离线设备，方便提前排好优先级或清理废弃设备 |
| **声音设置…** | 一键快捷打开 macOS 系统的声音控制面板 |

> ⏸️ **暂停自动接管**：如果临时需要完全手动掌控，可在右上角菜单中关闭“自动切换设备”。面板顶部会显示橙色“自动切换已暂停”胶囊，点击即可一键恢复。

---

## ⚙️ 工作原理

1. **硬件监听**：调用 CoreAudio 底层 C API（`AudioObjectAddPropertyListenerBlock`）实时监听音频硬件注册表，毫秒级响应插拔与默认设备变动；
2. **唯一标识**：以硬件唯一 UID 绑定优先级，即使拔掉设备或重启 Mac，设置依然完整保留（保存在 `io.github.realruian.SoundPin` 偏好域）；
3. **启发式识别**：结合设备的 `kAudioDevicePropertyTransportType`（USB、Bluetooth、HDMI、DisplayPort 等）以及内置品牌声学关键词库，精准分离耳机与扬声器。

查看本地偏好配置：
```bash
defaults read io.github.realruian.SoundPin
```

---

## ⚠️ 已知限制与注意事项

- **极少见的小众品牌蓝牙耳机**：若未命中内置声学关键词库，可能初次连接时会被分入扬声器组。只需在面板悬停其右侧 `⋯` 菜单选择“移到耳机”即可，后续将永久生效；
- **AirPlay 隔空播放**：未主动连接的隔空播放设备不会出现在列表中；
- **蓝牙设备管理**：本工具负责已连接设备的音频流调度，不承担蓝牙配对与主动连接功能。

---

## 🗑️ 卸载

在菜单栏面板的 `⋯` 菜单中点击“退出”，随后在终端运行：

```bash
rm -rf /Applications/SoundPin.app
defaults delete io.github.realruian.SoundPin
```

---

## 🛠️ 本地开发与工具集

仓库内置了完善的离线调试与打包工具链：

- `tools/render-preview.sh [输出.png] [--demo] [--lang en|zh-Hans]`：利用 SwiftUI 离线渲染高保真预览图，无需反复物理插拔设备截图；
- `tools/check-devices.sh`：快速测试常见音频设备的自动分组与图标匹配规则；
- `tools/make-dmg.sh`：一键构建通用架构并输出 Release DMG 打包文件。

---

## 🤝 致谢

本项目基于 [tobi/AudioPriorityBar](https://github.com/tobi/AudioPriorityBar) 进行深度重构与功能演进。感谢原作者 tobi 优雅的核心调度设计。2.1 及之前的版本沿用原名 Audio Priority Bar，2.2 起改名为 SoundPin（定音）。

**相比原版的核心升级**：
- 🎨 **界面重构**：完全按照 macOS 原生声音控制中心重制 UI，视觉更现代、更精致；
- 👆 **交互优化**：支持“点击设备直接切换并置顶优先级”（原版在自动模式下点击设备无响应）；
- 🌐 **国际化支持**：新增中英双语架构，默认跟随系统；
- 🎧 **图标与状态联动**：菜单栏图标实时呈现音量分段、静音状态与当前耳机型号；
- 🖥️ **抗误判引擎**：针对 HDMI/DisplayPort 屏幕音频增加传输通道过滤，防止被误判为耳机；
- 🧩 **系统兼容性**：修复了高版本 macOS 菜单栏弹窗偶发折叠与空白的问题。

---

## 📄 许可证

本项目遵循 [MIT License](LICENSE)。
