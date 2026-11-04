# OpenCode 额度小组件

OpenCode Go 订阅额度的桌面小组件，提供 macOS 原生 WidgetKit 版和 Windows 悬浮球版。

## Windows 版

桌面悬浮球 + 三个同心进度环，悬停展开成长条卡片，拖到屏幕左右边缘会吸附成竖条，前台全屏时自动隐藏。

| 悬浮球 | 悬停展开 | 边缘吸附 |
| --- | --- | --- |
| <img src="windows/docs/ball.png" width="150" alt="Windows 悬浮球"> | <img src="windows/docs/card.png" width="360" alt="Windows 展开卡片"> | <img src="windows/docs/dock.png" width="90" alt="Windows 边缘吸附竖条"> |

双击、右键菜单、刷新间隔等细节见 [`windows/README.md`](windows/README.md)。

## macOS 版

macOS **原生桌面小组件**（WidgetKit），在桌面右键 →「编辑小组件…」里搜索 “OpenCode” 添加，可自由拖动摆放。

展示 OpenCode Go 订阅三档额度的**剩余百分比**和**重置倒计时**：

| 档位 | 对应字段 | 说明 |
| --- | --- | --- |
| 5 小时 | `go.rolling` | 滚动 5 小时窗口 |
| 周限额 | `go.weekly` | 每周重置 |
| 月限额 | `go.monthly` | 每月重置 |

支持两种小组件，可在列表里分别添加：

- **OpenCode 额度**：列表样式，小号（158×158）/ 中号（338×158）
- **OpenCode 额度 · 圆环**：仅小号，三个进度环（5 小时 / 周 / 月），环内百分比、环下重置倒计时，右上角显示更新时间和状态

两者共用同一套数据和设置。

### 预览

| 列表版（中号） | 圆环版（小号） |
| --- | --- |
| ![列表版](docs/preview-medium.png) | ![圆环版](docs/preview-rings.png) |

### 组成

```
OpenCodeMeter.app                  宿主 App（菜单栏常驻，无 Dock 图标）
└── Contents/PlugIns/
    └── OpenCodeMeterWidget.appex  WidgetKit 扩展（沙盒）
```

- **宿主 App**：每 60 秒读取一次本机 OpenCode 服务，把登录凭证和最新额度镜像到小组件的沙盒容器里，并通知 WidgetKit 刷新时间线。菜单栏显示 5h 档的剩余百分比，点开可刷新、打开用量详情、查看添加小组件的步骤、退出。
- **小组件扩展**：优先自己请求本地服务（即使宿主 App 没在运行也能刷新）；服务不可用时回退到宿主 App 留下的缓存，并标注「离线」。

### 数据来源

OpenCode 桌面端会在本机运行一个共享服务，并写一个注册文件：

```
~/.local/state/opencode/service.json
{
  "url": "http://127.0.0.1:49374",
  "password": "...",
  ...
}
```

宿主 App 读取该文件拿到随机端口和口令，请求：

```
GET {url}/api/experimental/usage/limits
Authorization: Basic base64("opencode:" + password)
```

返回示例：

```json
{
  "data": {
    "go": {
      "rolling": { "percent": 0, "limited": false, "resetsAt": 1793687085000 },
      "weekly":  { "percent": 2, "limited": false, "resetsAt": 1794182400000 },
      "monthly": { "percent": 1, "limited": false, "resetsAt": 1796178951000 }
    }
  }
}
```

- `percent` 是**已用**百分比，界面显示 `100 - percent`。
- `resetsAt` 是毫秒时间戳，换算成倒计时（如 `4h21m`、`5d22h`、`29d`）。
- 端口每次 OpenCode 重启都可能变化，宿主 App 每次刷新都会重读注册文件。

数据只在本机流转。

#### 宿主 App 与小组件如何共享数据

App Group 需要开发者 Team ID，这里改用普通用户目录 + 沙盒只读例外：

```
~/Library/Application Support/OpenCodeMeter/state.json
```

- 宿主 App（非沙盒）负责写入凭证、最新额度和界面设置
- 小组件通过 `com.apple.security.temporary-exception.files.home-relative-path.read-only` 只读该目录
- 小组件自己也能请求本地服务，所以宿主 App 没运行时仍可刷新

### 构建与安装

需要 **完整 Xcode**（不是只有 Command Line Tools）和 macOS 14+。

```bash
cd opencode-meter

./build.sh      # 用 xcodebuild 构建（含 .appex）
./install.sh    # 构建 + 安装到 /Applications + 注册 + 启动
```

> 为什么必须用 Xcode 构建：当前 macOS 的 WidgetKit 扩展走 ExtensionKit，需要 Xcode 注入的开发签名权限（`get-task-allow` 等）；用 `swiftc` 手工拼的 `.appex` 会被系统按旧式 XPC 拉起并在引导阶段崩溃。

工程文件 `OpenCodeMeter.xcodeproj` 已生成；修改 `project.yml` 后可重新生成（需要 `brew install xcodegen`）：

```bash
xcodegen generate
```

卸载：

```bash
pkill -f "OpenCodeMeter.app/Contents/MacOS/OpenCodeMeter" || true
rm -rf /Applications/OpenCodeMeter.app
rm -rf ~/Library/Application\ Support/OpenCodeMeter
defaults delete local.metax.opencode-meter 2>/dev/null || true
```

### 添加小组件

1. 打开一次 `/Applications/OpenCodeMeter.app`（确认菜单栏出现百分比）
2. 桌面空白处右键 →「编辑小组件…」
3. 搜索 “OpenCode”，选小号或中号，拖到桌面
4. 若列表里没有：重新运行 `./install.sh`，再打开一次 App

### 打开设置

- **菜单栏**：右上角有一个柱状图图标 + 当前 5h 剩余百分比（如 `97%`），点它展开菜单
- **设置窗口**：双击 `/Applications/OpenCodeMeter.app`，或菜单里的「设置…」
- 菜单栏图标被刘海、其它图标或 Bartender 之类工具挡住时，用设置窗口即可

### 菜单可调项

菜单和设置窗口内容一致：

- **显示**：剩余额度 / 已使用
- **变色阈值**：黄色阈值（剩余 ≤ 50/40/30/25/20/15/10%）、红色阈值（25/20/15/10/5%）
- **颜色**：正常 / 警告 / 危险分别可选 绿、薄荷、青、蓝、紫、粉、红、橙、黄、灰
- **刷新间隔**：1 / 2 / 3 / 5 / 10 / 15 / 30 / 60 分钟
- 立即刷新、打开用量详情、如何添加小组件、打开数据目录、退出

设置写入 `state.json`，改动后立即通知 WidgetKit 刷新；宿主 App 的同步定时器也会按新间隔重排。

### 刷新节奏

- 默认 3 分钟，可在菜单里调整；小组件时间线按该间隔请求。
- 宿主 App 按同一间隔同步，并在每次同步后主动 `reloadAllTimelines()`。
- WidgetKit 仍会按系统预算调度，极端情况下可能被降频；倒计时是渲染时算出的静态文本，最多滞后一个周期。

### 颜色规则

默认阈值：

| 剩余额度 | 颜色 |
| --- | --- |
| > 25% | 绿色 |
| ≤ 25% | 黄色 |
| ≤ 10% 或已限流 | 红色 |

阈值和三种颜色都可以在菜单里改。颜色同时作用于百分比数字和进度条（小号只有数字）。

### 命令行调试

```bash
BIN=/Applications/OpenCodeMeter.app/Contents/MacOS/OpenCodeMeter

$BIN --print            # 打印当前三档额度
$BIN --sync             # 立即同步一次并通知小组件刷新
$BIN --state            # 打印共享状态文件路径和内容
$BIN --snapshot ./out   # 渲染小号/中号/离线三张预览图
```

排查时可以临时指定注册文件位置（默认 `~/.local/state/opencode/service.json`）：

```bash
OPENCODE_SERVICE_FILE=/tmp/fake-service.json $BIN --print
```

### 已知限制

- 依赖 OpenCode 桌面端正在运行；关闭后小组件显示「离线」并保留上次数据。
- 首次添加小组件前需要启动过一次宿主 App（用于写入凭证）。
- 只读取 Go 订阅 allowance，不展示 Console 团队预算（`budgets` 字段目前为空）。
- 使用 ad-hoc 签名，未做公证；仅适合本机自用。
- WidgetKit 的刷新由系统调度，无法做到秒级实时。
