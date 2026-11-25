# UsageCenter

**UsageCenter** 是一款面向 macOS 26/27 原生 **Liquid Glass** 设计的菜单栏统一配额与余额监控应用，在单一状态栏组件内并列显示 **Claude**、**ChatGPT (Codex)**、**Google Antigravity** 的 **5 小时剩余配额与周剩余配额**，以及本地已登录 **DSH (DeepSeek)** 账户的 **API 可用余额**。

## 核心特性

- **纯白官方 SVG 图标与全亮色高对比度呈现**：内置四款纯白官方 `.svg` 矢量图标，状态栏与液态玻璃面板统一采用高亮白与天蓝/琥珀/亮红高对比度视觉，简明易读。
- **原生 macOS 27 Liquid Glass 无限高详情悬浮面板**：基于 `NSGlassEffectView`、`GlassEffectContainer` 与 `.glassEffect` 构建，点击菜单栏任一分段即精确锚定在该分段正下方弹出专属详情面板，完整自适应高度，无滚动截断。
- **全面对标 CodexMeter 的详细用量历史分析**：
  - 支持 **当前周期 / 近 7 天 / 近 14 天 / 近 30 天 / 按日历周或月浏览** 5 种模式。
  - 自动切分重置周期曲线、绘制理想匀速参考虚线、标记未记录区间阴影、计算区间观测消耗量及当前周期重置结余/耗尽时间预测，支持鼠标悬停逐点查看精确数值。
  - 支持 ChatGPT / Codex **7 天 / 30 天 / 90 天 / 1 年（按周聚合）/ 全部（按月聚合）** Token 活动柱状图、连续活跃天数、悬停检视与 CSV 导出。
- **纯本地 CLI 与已登录凭证驱动**：
  - **Claude**：`claude -p "/usage" --output-format json --no-session-persistence`
  - **ChatGPT**：`codex app-server --listen stdio://`（配额与每日 Token 活动）
  - **Antigravity**：`agy -p "/usage" --output-format json`
  - **DeepSeek**：自动读取 `~/.dsh/.credentials.yaml` 本地 DSH 登录账户余额与累计消耗

## 编译与安装

```bash
./Scripts/build_app.sh
./dist/UsageCenter.app/Contents/MacOS/UsageCenter --self-check
ditto dist/UsageCenter.app /Applications/UsageCenter.app
open /Applications/UsageCenter.app
```

## 许可证

MIT License
