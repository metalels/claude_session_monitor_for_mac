# Claude Session Monitor

Claude Code のセッションログをリアルタイムで監視・表示する macOS アプリケーション

## 機能

- **プロジェクト一覧表示**: `~/.claude/projects/` 配下のプロジェクトを自動検出
- **セッション一覧表示**: 選択したプロジェクトのセッションを一覧表示（最終更新日時順）
- **リアルタイムログ表示**: セッションログをリアルタイムで監視・表示
- **マークダウン対応**: メッセージをマークダウンとしてレンダリング
- **ツール表示の最適化**: Edit, Bash, Read, Write, Grep, Glob などのツール呼び出しを人間が読みやすい形式で表示
- **TodoWrite 対応**: タスクリストをステータス別に色分けして見やすく展開表示
- **フィルタリング機能**: メッセージタイプ、ツール種別、テキスト検索によるフィルタリング
- **設定機能**: 表示列の選択、空メッセージの表示/非表示、最後に開いたプロジェクトの記憶

## スクリーンショット

```
┌──────────┬──────────┬─────────────────────────────────────────┐
│ Projects │ Sessions │ Session Log                             │
│          │          │                                         │
│ proj-a   │ sess-1   │ [User] 12:00 メッセージ内容...          │
│ proj-b   │ sess-2   │ [Assistant] 12:01 応答内容...           │
│ proj-c   │ sess-3   │ ┌─ Edit ────────────────────────┐       │
│          │          │ │ File Path: /path/to/file      │       │
│          │          │ │ Old String: 置換前の内容...    │       │
│          │          │ │ New String: 置換後の内容...    │       │
│          │          │ └───────────────────────────────┘       │
└──────────┴──────────┴─────────────────────────────────────────┘
```

## 動作要件

- macOS 14.0 (Sonoma) 以降
- Apple Silicon / Intel Mac 対応

## ビルド手順

### 必要なツール

- Xcode 15.0 以降
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (プロジェクトファイル生成用)

### 1. XcodeGen のインストール

```bash
# Homebrew を使用
brew install xcodegen

# または Mint を使用
mint install yonaskolb/xcodegen
```

### 2. リポジトリのクローン

```bash
git clone <repository-url>
cd claude_session_monitor
```

### 3. Xcode プロジェクトの生成

```bash
xcodegen generate
```

### 4. ビルド

#### コマンドラインでビルド

```bash
# Debug ビルド
xcodebuild -project ClaudeSessionMonitor.xcodeproj -scheme ClaudeSessionMonitor -configuration Debug build

# Release ビルド
xcodebuild -project ClaudeSessionMonitor.xcodeproj -scheme ClaudeSessionMonitor -configuration Release build
```

#### Xcode でビルド

```bash
open ClaudeSessionMonitor.xcodeproj
```

Xcode で開いた後、`⌘+R` でビルド＆実行

### 5. アプリの場所

ビルド後、アプリは以下の場所に生成されます:

```
~/Library/Developer/Xcode/DerivedData/ClaudeSessionMonitor-*/Build/Products/Debug/Claude Session Monitor.app
```

## 使い方

1. アプリを起動
2. 左ペインからプロジェクトを選択
3. 中央ペインからセッションを選択
4. 右ペインでセッションログを確認

### フィルタリング

- **Type**: メッセージタイプ (User, Assistant, Summary, File History) でフィルタ
- **Tools**: 特定のツール (Edit, Bash, Read, Write, Grep, Glob など) でフィルタ
- **検索**: テキスト検索でメッセージを絞り込み
- **Auto-scroll**: 最新メッセージに自動スクロール（トグルで切り替え）

### 設定

ツールバーの歯車アイコンから設定画面を開けます:

| 設定項目 | 説明 | デフォルト |
|---------|------|-----------|
| Show Type Column | Type 列の表示 | ON |
| Show Time Column | Time 列の表示 | ON |
| Show Role Column | Role 列の表示 | ON |
| Show Empty Messages | 空メッセージの表示 | OFF |
| Remember Last Project | 最後に開いたプロジェクトを記憶 | ON |

## ディレクトリ構成

```
claude_session_monitor/
├── project.yml                          # XcodeGen 設定ファイル
├── README.md
└── ClaudeSessionMonitor/
    ├── App/
    │   └── ClaudeSessionMonitorApp.swift    # アプリエントリーポイント
    ├── Models/
    │   ├── Project.swift                    # プロジェクトモデル
    │   ├── Session.swift                    # セッションモデル
    │   └── SessionMessage.swift             # メッセージモデル
    ├── Views/
    │   ├── ContentView.swift                # メインビュー (3ペイン構成)
    │   ├── ProjectListView.swift            # プロジェクト一覧
    │   ├── SessionListView.swift            # セッション一覧
    │   ├── SessionLogView.swift             # ログ表示
    │   └── SettingsView.swift               # 設定画面
    ├── Services/
    │   ├── SessionFileWatcher.swift         # プロジェクト/セッション/ファイル監視
    │   └── SessionParser.swift              # JSONL パーサー
    └── Utils/
        └── Constants.swift                  # 定数定義
```

## セッションログの保存場所

Claude Code のセッションログは以下の場所に保存されています:

```
~/.claude/projects/{project-path}/{session-uuid}.jsonl
```

### メッセージタイプ

| タイプ | 説明 |
|-------|------|
| `user` | ユーザーの入力メッセージ |
| `assistant` | Claude の応答（テキスト、ツール呼び出し、思考を含む） |
| `summary` | セッションのサマリー |
| `file-history-snapshot` | ファイル変更履歴のスナップショット |

## 技術スタック

- **言語**: Swift 5.9+
- **UI フレームワーク**: SwiftUI
- **最小OS**: macOS 14.0+
- **ファイル監視**: DispatchSource (FSEvents)
- **JSON解析**: Codable + JSONSerialization
- **プロジェクト管理**: XcodeGen

## ライセンス

MIT License

## 作者

Claude Code で生成
