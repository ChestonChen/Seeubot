<div align="center">

<img src="docs/icon.png" width="116" alt="Seeubot" />

# Seeubot

**Mac のノッチに住む、Claude Code と Codex のセッションを可視化するかわいいダイナミックアイランド・ウィジェット。**

[English](README.md) · [简体中文](README.zh-CN.md) · **日本語**

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-blue)
![No Xcode](https://img.shields.io/badge/Xcode-不要-brightgreen)

<img src="docs/demo.gif" width="720" alt="Seeubot デモ" />

</div>

---

## 概要

Seeubot は Mac の**ノッチ**に常駐します。いくつの AI コーディングセッションが動いているか、そのうち**作業中**か**アイドル**か、消費トークン量が一目でわかります。ロボットのマスコットが瞬きしたり、きょろきょろしたり、作業中はおしゃべりしたり。ホバーするとフルダッシュボードに開きます。

すべて Claude Code と Codex がディスクに書き出すセッションファイルから**ローカルで**読み取ります。**通信なし・API キー不要・テレメトリなし。**

## 特長

- 🏝️ **ノッチに常駐** —— 小さなピルがホバーでダッシュボードに展開。
- 🤖 **動くマスコット** —— 瞬き・視線移動・首かしげ・ジャンプ・アンテナの揺れ、作業中はキラキラ。アイドル時は `zzz` で居眠り。
- 📊 **リアルタイム・ダッシュボード** —— セッション数、作業中/アイドル、トークン量（出力 / 入力 / キャッシュ作成 / キャッシュ読取）、Claude と Codex の内訳、各セッションのチップ。
- 🎛️ **2 つの形態** —— ノッチ下の**ピル**、またはノッチを跨ぐ**バー**。ノッチが**ない** Mac では自動で 1 本のフラットバーになります。
- 🖱️ **どこからでも操作** —— ダッシュボードの `⋯` ボタンとメニューバーアイコン：表示/非表示、形態切替、アップデート確認、**終了**。
- 🔔 **アップデート通知** —— 新バージョンをお知らせ。
- 🪶 **軽量ネイティブ** —— 単一の SwiftUI バイナリ。Command Line Tools でビルド（**Xcode 不要**）、依存なし。

<div align="center">
<img src="docs/expanded.png" width="380" alt="ダッシュボード" />
</div>

## インストール

### ワンライナー

ソースからビルドし `/Applications` にインストール、すぐ起動してログイン時に自動起動：

```bash
curl -fsSL https://raw.githubusercontent.com/ChestonChen/Seeubot/main/install.sh | bash
```

### ソースから

```bash
git clone https://github.com/ChestonChen/Seeubot.git
cd Seeubot && ./install.sh
```

> Apple シリコン Mac・**macOS 14+**・Command Line Tools（`xcode-select --install`）。Xcode は不要。

## 使い方

- ウィジェットに**ホバー** → ダッシュボードが開く。離れると閉じる。（折りたたみ時は下のクリックを妨げません。）
- ダッシュボードの **`⋯` ボタン**、またはメニューバーの**ゲージアイコン** → 形態切替・表示/非表示・アップデート確認・**終了**。

## 形態

| ピル（ノッチ有） | バー（ノッチ有） | フラット（ノッチ無） |
|:---:|:---:|:---:|
| <img src="docs/collapsed-hanging.png" width="230"/> | <img src="docs/collapsed-sides.png" width="230"/> | <img src="docs/collapsed-flat.png" width="230"/> |

## 仕組み

バックグラウンドのコレクターが**3 秒ごと**にローカルファイルを読み取ります：

| 指標 | ソース |
|------|--------|
| Claude のセッションとトークン | `~/.claude/projects/**/<uuid>.jsonl` —— 各 `assistant` メッセージの usage を合算、**`message.id` で重複排除**（`subagents/` は除外） |
| Codex のセッションとトークン | `~/.codex/sessions/**/rollout-*.jsonl` —— 最後の累積 `token_count` |
| 本日のトークン | 各エントリの**タイムスタンプ**で按分 |
| ライブセッション | 実行中の `claude` / `codex` プロセス（`ps` + `lsof` で cwd / 開いているトランスクリプト） |
| 作業中 / アイドル | トランスクリプトが **45 秒**以内に更新 = 作業中、それ以外はアイドル |

トークンは一度だけ解析し**ファイル単位でキャッシュ**（サイズ + 更新時刻）するため、毎回書き込み中のセッションだけを読み直します。ホバーはカーソル位置のポーリングで検出し、パネルはフォーカスを奪いません。

> トークン総量が数十億になるのは、**キャッシュ読取**（毎ターン読み直すコンテキスト）を含むためです。ダッシュボードはこれを分解し、実際に生成された *出力* を強調します。

## ロードマップ

- [x] メニューバー + ウィジェット内操作（表示/非表示・形態切替・終了）
- [x] ノッチなし Mac（フラットバー）
- [x] アップデート確認
- [x] Homebrew cask
- [ ] 🔔 **セッション完了時のデスクトップ通知 —— _次の目玉_。** エージェントは長いタスクの完了を即座に知らせてくれないことが多いので、Seeubot がセッションの「作業中」→アイドルの瞬間に通知をポップします。
- [ ] 🔌 他の AI CLI —— Cursor、Aider、Gemini CLI、Cline、opencode…
- [ ] ⚙️ 更新間隔・「作業中」判定の設定化
- [ ] 💵 コスト見積り（トークン → モデル別 $）
- [ ] 📈 履歴とトレンド
- [ ] 🧭 アプリ内自動アップデート

## アンインストール

```bash
launchctl unload ~/Library/LaunchAgents/com.chestonchen.seeubot.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.chestonchen.seeubot.plist
rm -rf /Applications/Seeubot.app
```

## FAQ

**Claude Code と Codex だけですか？** 今のところは。他ツールはセッション保存形式が異なり、個別対応が必要です（ロードマップ参照）。

**自動ですか？** 完全自動。3 秒ごとに再スキャンし、ログイン時に起動、トークンは使用に応じて加算されます。

**データを送信しますか？** いいえ。`~/.claude` と `~/.codex` 下のローカルファイルを読むだけです。

## コントリビュート

Issue・PR 歓迎——AI CLI の追加対応、翻訳、UI 改善は最初の一歩に最適です。

## ライセンス

[MIT](LICENSE)
