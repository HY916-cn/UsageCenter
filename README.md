# UsageCenter

**UsageCenter** 是一款原生 macOS 菜单栏配额与额度监控工具，结合 **Stats** 的模块化水平状态栏排列与 **CodexMeter** 的指示器、弹窗与历史分析体验，在单一菜单栏组件中同时展示 **Claude**、**ChatGPT (Codex)**、**Google Antigravity** 的 **5 小时剩余配额、每周剩余配额及对应剩余重置时间**，以及本地已登录 **DSH (DeepSeek)** 账户的 **API 可用余额与累计消耗**。

## 核心特性

- **官方 SVG 品牌图标 + Stats 模块化状态栏排列**：每段左侧内置官方矢量 `.svg` 图标（支持彩色图标与单色模板图标切换），各段可独立启用/隐藏并自由调整左右顺序。
- **CodexMeter 风格指示器与剩余配额展示**：默认展示**剩余配额百分比**，提供**同心双环（外环剩余配额 / 内蓝环剩余时间）+ 百分比**、**横向进度条**、**双进度条**、**底部紧凑条**、**双层纯文字**与**仅双环** 6 种菜单栏呈现形式，支持按分段独立覆盖样式。
- **分段独立点击详情弹窗**：点击菜单栏对应分段（Claude / ChatGPT / Antigravity / DeepSeek），即在该分段正下方弹出该服务专属的原生毛玻璃详情面板，包含剩余配额与剩余时间进度条、消耗进度状态（进度正常 / 超出进度）、重置倒计时、周期历史缩略图及近 30 天 Token 活动柱状图。
- **纯本地 CLI 与已登录凭证驱动**：
  - **Claude**：调用本地 `claude -p "/usage" --output-format json --no-session-persistence` 与 `claude auth status`。
  - **ChatGPT**：调用本地 `codex app-server --listen stdio://` 读取 `account/read`、`account/rateLimits/read` 与 `account/usage/read`（含近 30 天每日 Token 活动）。
  - **Antigravity**：调用本地 `agy -p "/usage" --output-format json` 读取各模型组的 5 小时与每周剩余限额。
  - **DeepSeek (DSH)**：自动读取本地 `~/.dsh/.credentials.yaml` 中已登录的 DSH 平台账户授权，查询充值余额、赠送余额与历史累计消耗（同时保留备用 API Key 与自定义 CLI 支持）。
- **Liquid Glass 用量历史窗口与通知提醒**：内置独立的全尺寸用量历史窗口（支持当前周期 / 近 7 天 / 14 天 / 30 天趋势曲线、Token 活动图表与 CSV 导出）以及低配额 / 超速本地通知提醒。

## 编译、自检与安装

```bash
# 编译 Release 并签名打包 dist/UsageCenter.app
chmod +x Scripts/build_app.sh
./Scripts/build_app.sh

# 运行 SVG、解析器与本机四项服务实时联调自检
./dist/UsageCenter.app/Contents/MacOS/UsageCenter --self-check

# 安装至系统应用程序目录并启动
ditto dist/UsageCenter.app /Applications/UsageCenter.app
open /Applications/UsageCenter.app
```

## 许可证

MIT License
