# UsageCenter

**UsageCenter** 是一款原生 macOS 菜单栏状态组件，在**单一菜单栏组件**内同时展示 **Claude**、**ChatGPT (Codex)**、**Google Antigravity** 的 **5 小时用量、周用量及其对应重置时间**，以及 **DeepSeek API 余额**。所有数据均通过本机 CLI 获取，详情弹窗与设置窗口采用 macOS Liquid Glass 液态玻璃风格（在旧版系统自动回退为系统毛玻璃材质）。

## 核心特性

- **单组件多段并列展示**：在一个 `NSStatusItem` 中同时呈现四个服务，每一段均配有对应的专属品牌矢量图标（支持彩色品牌图标与单色自适应图标切换）。
- **独立分段点击详情**：点击菜单栏中的任意服务分段（Claude / ChatGPT / Antigravity / DeepSeek），即在该分段正下方弹出对应服务的 Liquid Glass 详情面板；右键任意位置可快速刷新全部、打开设置或退出。
- **纯本地 CLI 驱动**：
  - **Claude**：调用本地 `claude -p "/usage" --output-format json --no-session-persistence` 与 `claude auth status` 解析 5 小时会话限额、每周限额与精确重置时间。
  - **ChatGPT**：调用本地 `codex app-server --listen stdio://` 通过 JSON-RPC 读取 5 小时与每周配额窗口及重置时间。
  - **Antigravity**：调用本地 `agy -p "/usage" --output-format json` 读取 `Gemini Models` 与 `Claude and GPT models` 各模型组的 5 小时及周配额与重置时间。
  - **DeepSeek**：通过 macOS 系统钥匙串安全读取 API Key 并调用本地 `curl`（经标准输入安全传递鉴权头）查询官方余额接口，亦支持配置自定义本地 CLI 命令。
- **高自由度呈现设置与实时预览**：
  - 支持独立开关各服务分段、自由调整左右排列顺序，并在设置顶部实时预览状态栏渲染效果。
  - 提供 **双行堆叠（5h + 周 + 时间）**、**同心双环 + 数值**、**双进度条 + 数值**、**单行紧凑数值**、**极简图标与图形** 5 种呈现形式，支持全局统一或按分段单独指定。
  - 支持切换 **已用比例 (Used%) / 剩余比例 (Remaining%)**、**重置倒计时 / 重置时间点 / 隐藏时间**。

## 环境要求

- macOS 13.0 或更高版本（macOS 26+ 原生启用 Liquid Glass 液态玻璃材质）
- Swift 5.9+（Command Line Tools 或 Xcode）
- 按需安装并登录本地 CLI：`claude`、`codex`、`agy`（以及系统自带 `curl` 或自定义 DeepSeek CLI）

## 编译、自检与运行

```bash
# 打包并签名生成 dist/UsageCenter.app
chmod +x Scripts/build_app.sh
./Scripts/build_app.sh

# 运行解析断言与本机 CLI 联调自检
./dist/UsageCenter.app/Contents/MacOS/UsageCenter --self-check

# 启动菜单栏应用
open dist/UsageCenter.app
```

## 许可证

MIT License
