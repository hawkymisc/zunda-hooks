#!/bin/bash
# scripts/install-hooks.sh
# ずんだもん hooks を Claude Code の設定にインストールする
#
# 使用方法:
#   bash scripts/install-hooks.sh                    # ユーザースコープ (~/.claude/settings.json)
#   bash scripts/install-hooks.sh --user             # 同上（明示）
#   bash scripts/install-hooks.sh --project /path/to/project  # プロジェクトスコープ
#
# 追加されるフック:
#   SessionStart  → zunda-session-start.sh (async)
#   SessionEnd    → zunda-session-end.sh
#   PreToolUse    → zunda-speak.sh (async)
#   PostToolUse   → zunda-speak.sh (async)
#
# 注意:
#   - 同一コマンドが既に登録済みの場合はスキップ（冪等）
#   - 変更前に <対象ファイル>.bak としてバックアップを作成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_DIR/.claude/hooks"

# ── オプション解析 ──────────────────────────────────────────────────────────
TARGET_MODE="user"
PROJECT_DIR=""

usage() {
  echo "使用方法: $0 [--user | --project <project-dir>]" >&2
  echo ""
  echo "  --user               ユーザースコープにインストール (デフォルト)" >&2
  echo "  --project <dir>      指定したプロジェクトディレクトリにインストール" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      TARGET_MODE="user"
      shift ;;
    --project)
      TARGET_MODE="project"
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --project の後にディレクトリを指定してください" >&2
        usage
      fi
      PROJECT_DIR="$2"
      shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "ERROR: 不明なオプション: $1" >&2
      usage ;;
  esac
done

# ── インストール先の決定 ─────────────────────────────────────────────────────
if [ "$TARGET_MODE" = "user" ]; then
  TARGET_SETTINGS="$HOME/.claude/settings.json"
  echo "=== ずんだもん hooks インストーラー (ユーザースコープ) ==="
else
  if [ -z "$PROJECT_DIR" ]; then
    echo "ERROR: --project にディレクトリが指定されていません" >&2
    exit 1
  fi
  if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: ディレクトリが見つかりません: $PROJECT_DIR" >&2
    exit 1
  fi
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
  TARGET_SETTINGS="$PROJECT_DIR/.claude/settings.json"
  echo "=== ずんだもん hooks インストーラー (プロジェクトスコープ) ==="
  echo "プロジェクト: $PROJECT_DIR"
fi

echo "リポジトリ: $REPO_DIR"
echo "設定ファイル: $TARGET_SETTINGS"
echo ""

# ── 前提チェック ─────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq が見つかりません。インストールしてください:" >&2
  echo "  sudo apt install jq" >&2
  exit 1
fi

if [ ! -f "$TARGET_SETTINGS" ]; then
  if [ "$TARGET_MODE" = "project" ]; then
    echo "設定ファイルが存在しないため作成します: $TARGET_SETTINGS"
    mkdir -p "$(dirname "$TARGET_SETTINGS")"
    echo '{}' > "$TARGET_SETTINGS"
  else
    echo "ERROR: $TARGET_SETTINGS が見つかりません" >&2
    exit 1
  fi
fi

for script in zunda-speak.sh zunda-session-start.sh zunda-session-end.sh; do
  if [ ! -f "$HOOKS_DIR/$script" ]; then
    echo "ERROR: $HOOKS_DIR/$script が見つかりません" >&2
    exit 1
  fi
done

# ── バックアップ ──────────────────────────────────────────────────────────────
cp "$TARGET_SETTINGS" "${TARGET_SETTINGS}.bak"
echo "バックアップ: ${TARGET_SETTINGS}.bak"
echo ""

# ── フックコマンド定義 ────────────────────────────────────────────────────────
# session-start は CLAUDE_PROJECT_DIR を env で渡す（initial_warning.wav の参照に必要）
SESSION_START_CMD="CLAUDE_PROJECT_DIR=\"${REPO_DIR}\" bash \"${HOOKS_DIR}/zunda-session-start.sh\""
SESSION_END_CMD="bash \"${HOOKS_DIR}/zunda-session-end.sh\""
SPEAK_CMD="bash \"${HOOKS_DIR}/zunda-speak.sh\""

# ── settings.json にフックを追加（冪等） ────────────────────────────────────
UPDATED=$(jq \
  --arg ss_cmd "$SESSION_START_CMD" \
  --arg se_cmd "$SESSION_END_CMD" \
  --arg sp_cmd "$SPEAK_CMD" \
  '
  # イベントの hooks 配列に指定コマンドが既に存在するか確認
  def has_cmd(event; cmd):
    (.hooks[event] // [])
    | map(.hooks // [] | map(.command // "") | any(. == cmd))
    | any;

  # 重複しない場合のみ追加
  def add_hook(event; hook_entry):
    .hooks[event] //= [] |
    if has_cmd(event; hook_entry.hooks[0].command) then .
    else .hooks[event] += [hook_entry]
    end;

  add_hook("SessionStart"; {"hooks": [{"type": "command", "command": $ss_cmd, "async": true}]}) |
  add_hook("SessionEnd";   {"hooks": [{"type": "command", "command": $se_cmd, "async": false}]}) |
  add_hook("PreToolUse";   {"hooks": [{"type": "command", "command": $sp_cmd, "async": true}]}) |
  add_hook("PostToolUse";  {"hooks": [{"type": "command", "command": $sp_cmd, "async": true}]})
  ' "$TARGET_SETTINGS")

echo "$UPDATED" > "$TARGET_SETTINGS"

echo "インストール完了!"
echo ""
echo "追加されたフック:"
echo "  SessionStart  → zunda-session-start.sh (async=true)"
echo "  SessionEnd    → zunda-session-end.sh   (async=false)"
echo "  PreToolUse    → zunda-speak.sh         (async=true)"
echo "  PostToolUse   → zunda-speak.sh         (async=true)"
echo ""
echo "次のステップ:"
echo "  1. VOICEVOX を起動: \$HOME/.voicevox/VOICEVOX.AppImage --no-sandbox"
echo "  2. 音声キャッシュを生成: bash scripts/pregenerate.sh"
