<div align="center">

# UsageCenter

**macOS 菜单栏 AI 用量中心——在一个原生面板中查看 Claude、ChatGPT、Antigravity 与 DeepSeek。**

[![macOS](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Liquid%20Glass-0071E3?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

[![Stars](https://img.shields.io/github/stars/HY916-cn/UsageCenter?logo=github&label=Stars)](https://github.com/HY916-cn/UsageCenter/stargazers)
[![Forks](https://img.shields.io/github/forks/HY916-cn/UsageCenter?logo=github&label=Forks)](https://github.com/HY916-cn/UsageCenter/network/members)
[![Last Commit](https://img.shields.io/github/last-commit/HY916-cn/UsageCenter?logo=git&logoColor=white)](https://github.com/HY916-cn/UsageCenter/commits/main)
[![Repo Size](https://img.shields.io/github/repo-size/HY916-cn/UsageCenter)](https://github.com/HY916-cn/UsageCenter)
[![Issues](https://img.shields.io/github/issues/HY916-cn/UsageCenter?logo=github&label=Issues)](https://github.com/HY916-cn/UsageCenter/issues)

通过已登录的本地 CLI 读取配额与 Token 活动，<br/>
并在原生 Liquid Glass 界面中统一展示周期、趋势、预测和余额。

</div>

---

## 核心特性

- **四个服务，一个入口**：在单个菜单栏组件中并列展示 Claude、ChatGPT (Codex)、Google Antigravity 的 5 小时与每周配额，以及 DeepSeek API 余额。
- **原生 Liquid Glass**：基于 `NSGlassEffectView`、`GlassEffectContainer` 与 SwiftUI `.glassEffect` 构建，详情面板锚定到对应的菜单栏分段。
- **多维用量趋势**：支持当前周期、近 7/14/30 天、按日历周或月浏览，并自动切分重置周期。
- **可解释的用量预测**：绘制理想匀速参考线和未记录区间，计算观测消耗量、重置结余与预计耗尽时间。
- **Token 活动分析**：提供 ChatGPT / Codex 7 天、30 天、90 天、1 年和全部时间视图，支持连续活跃天数、悬停检视与 CSV 导出。
- **纯本地集成**：使用本机已登录的官方 CLI；DeepSeek 可读取 DSH 登录态，也可从 macOS 钥匙串取用户配置的 API Key。

## 数据来源

| 服务 | 本地命令或凭据 | 展示内容 |
| --- | --- | --- |
| Claude | `claude -p "/usage" --output-format json --no-session-persistence` | 5 小时、每周及模型配额 |
| ChatGPT | `codex app-server --listen stdio://` | Codex 配额与每日 Token 活动 |
| Antigravity | `agy -p "/usage" --output-format json` | 5 小时与每周配额 |
| DeepSeek | `~/.dsh/.credentials.yaml` 或 macOS 钥匙串 | API 可用余额与累计消耗 |

UsageCenter 不读取 Claude、Codex 或 Antigravity 的凭据文件；它调用对应 CLI 的用量命令并解析返回结果。

## 下载安装

1. 从 [GitHub Releases](https://github.com/HY916-cn/UsageCenter/releases) 下载最新的 `.dmg` 或 `-macOS.zip`。
2. 将 `UsageCenter.app` 拖入 `/Applications`。
3. 确保要监控的 CLI 已安装并在终端登录，然后启动 UsageCenter。

运行要求：macOS 26 或更高版本，Apple Silicon Mac。当前发布包为 `arm64` 构建。

当前发布包使用本地 ad-hoc 签名，未经 Apple 公证。首次打开时如果 Gatekeeper 拦截，请确认安装包来自本仓库 Releases，然后在 Finder 中按住 Control 点击应用并选择「打开」；如仍被阻止，可在「系统设置 → 隐私与安全性」中对该应用选择「仍要打开」。

## 源码编译

需要 macOS 26+ 和 Swift 6.2 或更高版本的工具链。

```bash
git clone https://github.com/HY916-cn/UsageCenter.git
cd UsageCenter
./Scripts/build_app.sh
./dist/UsageCenter.app/Contents/MacOS/UsageCenter --self-check
```

构建脚本会生成并本地签名 `dist/UsageCenter.app`。如需安装到应用程序目录：

```bash
ditto dist/UsageCenter.app /Applications/UsageCenter.app
open /Applications/UsageCenter.app
```

## 测试

测试使用 `XCTest`，需要包含完整 macOS 测试框架的 Xcode 工具链。

```bash
swift test
```

测试集覆盖 Claude、Codex、Antigravity 与 DSH / DeepSeek 的命令输出解析。

## 项目结构

```text
Sources/UsageCenter/          菜单栏界面、设置、详情与历史窗口
Sources/UsageCenterCore/      CLI 执行、输出解析、数据模型与本地历史
Tests/UsageCenterCoreTests/   CLI 解析测试
Scripts/                     App 打包与图标生成脚本
```

## 本地数据与凭据

- 用量历史保存在 `~/Library/Application Support/UsageCenter/usage_history_v2.json`，用于趋势图、周期分析与 CSV 导出。
- 手动填入的 DeepSeek API Key 保存在 macOS 钥匙串中。
- 数据源请求由本地 CLI 或 DeepSeek / DSH 官方接口完成。

## License

本项目基于 [MIT License](LICENSE) 开源。
