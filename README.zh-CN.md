<div align="center">

<img src="docs/icon.png" width="116" alt="Seeubot" />

# Seeubot

**贴在 Mac 刘海上的可爱灵动岛小组件，实时统计你的 Claude Code 与 Codex 会话。**

[English](README.md) · **简体中文** · [日本語](README.ja.md)

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue)
![No Xcode](https://img.shields.io/badge/无需-Xcode-brightgreen)

<img src="docs/demo.gif" width="720" alt="Seeubot 演示" />

</div>

---

## 这是什么

Seeubot 住在 Mac 的**刘海**里。一眼就能看到有多少个 AI 编程会话在运行、多少在**工作中**、多少**空闲**、烧了多少 token——还有一只会眨眼、东张西望、工作时叽叽喳喳的机器人。鼠标移上去，它会弹开成一个完整看板。

所有数据都从 Claude Code 和 Codex 本地写在磁盘上的会话文件读取。**不联网、无需 API Key、无任何遥测。**

## 功能

- 🏝️ **住在刘海** —— 一个小药丸，鼠标悬停即展开成看板。
- 🤖 **会动的机器人** —— 眨眼、看来看去、歪头、蹦跳、天线摇曳，工作时冒星星；空闲时打盹飘 `zzz`。
- 📊 **实时看板** —— 会话总数、工作/空闲、Token 吞吐（输出 / 输入 / 建缓存 / 读缓存）、Claude vs Codex 分栏、每个实时会话的芯片。
- 🎛️ **两种形态** —— 刘海下方的**药丸**，或横跨刘海的**长条**；**没有刘海**的 Mac 会自动变成一条平铺长条。
- 🖱️ **随处可控** —— 看板里的 `⋯` 按钮，以及菜单栏图标：显示/隐藏、切换形态、检查更新、**退出**。
- 🔔 **更新提示** —— 有新版本会提示你。
- 🪶 **小巧原生** —— 单个 SwiftUI 二进制，用命令行工具即可编译（**无需 Xcode**），零依赖。

<div align="center">
<img src="docs/expanded.png" width="380" alt="看板" />
</div>

## 安装

### 一行命令

从源码编译、安装到 `/Applications`、立即启动并开机自启：

```bash
curl -fsSL https://raw.githubusercontent.com/ChestonChen/Seeubot/main/install.sh | bash
```

### 从源码

```bash
git clone https://github.com/ChestonChen/Seeubot.git
cd Seeubot && ./install.sh
```

> Apple 芯片 Mac、**macOS 14+**、已装命令行工具（`xcode-select --install`）。无需 Xcode。

## 使用

- **悬停**组件 → 展开成看板；移开 → 收起。（折叠时不会拦截下方窗口的点击。）
- 看板里的 **`⋯` 按钮**，或菜单栏的**仪表盘图标** → 切换形态、显示/隐藏、检查更新、**退出**。

## 形态

| 下挂（有刘海） | 长条（有刘海） | 平铺（无刘海） |
|:---:|:---:|:---:|
| <img src="docs/collapsed-hanging.png" width="230"/> | <img src="docs/collapsed-sides.png" width="230"/> | <img src="docs/collapsed-flat.png" width="230"/> |

## 原理

后台采集器**每 3 秒**读取本地文件：

| 指标 | 来源 |
|------|------|
| Claude 会话与 token | `~/.claude/projects/**/<uuid>.jsonl` —— 各 `assistant` 消息的 usage 累加，**按 `message.id` 去重**（跳过 `subagents/`） |
| Codex 会话与 token | `~/.codex/sessions/**/rollout-*.jsonl` —— 最后一条累计 `token_count` |
| 今日 token | 按每条记录的**时间戳**归属 |
| 实时会话 | 运行中的 `claude` / `codex` 进程（`ps` + `lsof` 取 cwd / 打开的会话文件） |
| 工作 / 空闲 | 会话文件 **45 秒**内有写入 = 工作中，否则空闲 |

token 只解析一次并**按文件缓存**（大小 + 修改时间），所以每次只重读正在写入的会话。悬停用轮询光标位置实现，面板永不抢焦点。

> token 总量常达数十亿，因为包含了**缓存读取**（每轮重读的上下文）。看板把它拆开，并高亮 *输出*——真正生成的 token。

## 后续规划

- [x] 菜单栏 + 组件内控制（显示/隐藏、切换形态、退出）
- [x] 无刘海 Mac（平铺长条）
- [x] 更新检查
- [x] Homebrew cask
- [ ] 🔔 **会话完成弹窗提醒 —— _下一个重点_。** AI 工具跑完长任务往往不能第一时间通知你；Seeubot 将在会话从「工作中」变为空闲的瞬间弹窗提醒。
- [ ] 🔌 更多 AI CLI —— Cursor、Aider、Gemini CLI、Cline、opencode…
- [ ] ⚙️ 可配置刷新间隔与「工作」判定窗口
- [ ] 💵 成本估算（token → 各模型 $）
- [ ] 📈 历史与趋势
- [ ] 🧭 应用内自动更新

## 卸载

```bash
launchctl unload ~/Library/LaunchAgents/com.chestonchen.seeubot.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.chestonchen.seeubot.plist
rm -rf /Applications/Seeubot.app
```

## 常见问题

**只统计 Claude Code 和 Codex 吗？** 目前是的——其它工具的会话存储方式不同，需要各自适配（见规划）。

**是自动的吗？** 完全自动。每 3 秒重扫、开机自启，token 随使用自动累加。

**会上传我的数据吗？** 不会。只读 `~/.claude` 和 `~/.codex` 下的本地文件。

## 贡献

欢迎 Issue 和 PR——适配更多 AI CLI、翻译、UI 打磨都是很好的起点。

## 许可

[MIT](LICENSE)
