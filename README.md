# zunda-hooks

Claude Code のツール実行時にずんだもん（VOICEVOX）が喋る Claude Code フック集。

音声合成のレイテンシを減らすため `~/.claude/hooks/zaudio/` に WAV を事前キャッシュします。
キャッシュがあれば即再生、なければ VOICEVOX で合成してキャッシュに保存します。

## 要件

| ツール | 確認コマンド |
|---|---|
| jq | `jq --version` |
| aplay または paplay | `aplay --version` |
| curl | `curl --version` |
| python3 | `python3 --version` |
| VOICEVOX (v0.25.1+) | `~/.voicevox/VOICEVOX.AppImage` |

### jq のインストール（未インストールの場合）

```bash
sudo apt install jq   # Debian/Ubuntu
```

## セットアップ

### 1. VOICEVOX を起動

```bash
~/.voicevox/VOICEVOX.AppImage --no-sandbox &
# エンジンが起動するまで数秒待つ
curl http://localhost:50021/version
```

### 2. 音声を事前生成

```bash
bash scripts/pregenerate.sh
```

全ツール用の WAV が `~/.claude/hooks/zaudio/` に生成されます。

### 3. Claude Code を開く

プロジェクトディレクトリで Claude Code を起動すると自動的にフックが有効になります。
`Read` や `Bash` ツールが実行されるたびにずんだもんが喋ります。

## 発話テキスト

| イベント | ツール | 発話 |
|---|---|---|
| PreToolUse | Bash | コマンドを実行するのだ |
| PreToolUse | Write | ファイルを書き込むのだ |
| PreToolUse | Edit | ファイルを編集するのだ |
| PreToolUse | Read | ファイルを読むのだ |
| PreToolUse | Glob | ファイルを探すのだ |
| PreToolUse | Grep | ファイルを検索するのだ |
| PreToolUse | その他 | {tool_name}を使うのだ |
| PostToolUse | Bash | コマンドが完了したのだ |
| PostToolUse | Write | 書き込みが完了したのだ |
| PostToolUse | Edit | 編集が完了したのだ |
| PostToolUse | その他 | {tool_name}が完了したのだ |

## キャッシュ管理

```bash
# キャッシュをリセット（再度 pregenerate.sh を実行してください）
rm ~/.claude/hooks/zaudio/*.wav

# キャッシュの確認
ls -lh ~/.claude/hooks/zaudio/
```

## VOICEVOX の自動起動・終了

- **SessionStart**: VOICEVOX が未起動なら自動起動します
- **SessionEnd**: 他のセッションがなければ VOICEVOX を自動終了します

セッション管理ファイル: `~/.claude/hooks/zaudio/.sessions/`

## 初回警告

`pregenerate.sh` 未実行（キャッシュ 0 件）の場合、セッション開始時に警告音声を再生します:

> 「見知らぬ人のつくったhooksをよく見ないままインストールして使うことは、とても危険なのだ」

警告音声は `assets/initial_warning.wav` としてリポジトリに含まれています。

## トラブルシュート

### 音声が再生されない

1. VOICEVOX が起動しているか確認: `curl http://localhost:50021/version`
2. aplay が使えるか確認: `aplay --version`
3. キャッシュが生成されているか確認: `ls ~/.claude/hooks/zaudio/`
4. jq がインストールされているか確認: `jq --version`

### VOICEVOX が起動しない

X11/ディスプレイが必要な場合:

```bash
# Xvfb を使ってヘッドレス起動
xvfb-run ~/.voicevox/VOICEVOX.AppImage --no-sandbox &
```

### フックが動いているか確認する

Claude Code の verbose モード（Ctrl+O）でフックの出力を確認できます。

## ファイル構成

```
.claude/
  settings.json          # フック設定（プロジェクトスコープ）
  settings.local.json    # 権限設定
  hooks/
    zunda-speak.sh        # PreToolUse/PostToolUse 共用スクリプト
    zunda-session-start.sh # SessionStart フック
    zunda-session-end.sh   # SessionEnd フック
scripts/
  pregenerate.sh         # 事前キャッシュ生成スクリプト
assets/
  initial_warning.wav    # 初回警告音声（リポジトリに含む）
```

## キャッシュの場所

`~/.claude/hooks/zaudio/` はユーザーホームに置かれるため、
複数プロジェクトで共有されます（再生成不要）。
