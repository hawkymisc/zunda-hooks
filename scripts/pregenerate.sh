#!/bin/bash
# 事前に全音声をキャッシュ生成するスクリプト
# 実行前に VOICEVOX を起動しておくこと（http://localhost:50021）
#
# 使用方法:
#   bash scripts/pregenerate.sh

CACHE_DIR="$HOME/.claude/hooks/zaudio"
VOICEVOX_URL="http://localhost:50021"
SPEAKER=3

# VOICEVOX が起動しているか確認
if ! curl -sf --connect-timeout 3 "${VOICEVOX_URL}/version" >/dev/null 2>&1; then
  echo "ERROR: VOICEVOX が起動していません。先に起動してください。" >&2
  echo "  ~/.voicevox/VOICEVOX.AppImage --no-sandbox &" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"

# ツール音声を生成してキャッシュへ保存する関数
generate() {
  local key="$1" text="$2"
  local file="$CACHE_DIR/${key}.wav"
  if [ -f "$file" ]; then
    echo "skip: $key (already cached)"
    return
  fi
  ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$text")
  QUERY=$(curl -sf --connect-timeout 5 -X POST \
    "${VOICEVOX_URL}/audio_query?text=${ENCODED}&speaker=${SPEAKER}" \
    -H "Content-Type: application/json")
  if [ -z "$QUERY" ]; then
    echo "ERROR: audio_query failed for '$key'" >&2
    return 1
  fi
  curl -sf --connect-timeout 10 -X POST \
    "${VOICEVOX_URL}/synthesis?speaker=${SPEAKER}" \
    -H "Content-Type: application/json" \
    -d "$QUERY" \
    -o "$file"
  echo "generated: $key  「$text」"
}

# assets/initial_warning.wav を生成（リポジトリにコミットして配布する）
generate_to_assets() {
  local text="見知らぬ人のつくったhooksをよく見ないままインストールして使うことは、とても危険なのだ"
  local script_dir
  script_dir="$(cd "$(dirname "$0")/.." && pwd)"
  local outfile="${script_dir}/assets/initial_warning.wav"
  mkdir -p "$(dirname "$outfile")"
  if [ -f "$outfile" ]; then
    echo "skip: assets/initial_warning.wav (already exists)"
    return
  fi
  ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$text")
  QUERY=$(curl -sf --connect-timeout 5 -X POST \
    "${VOICEVOX_URL}/audio_query?text=${ENCODED}&speaker=${SPEAKER}" \
    -H "Content-Type: application/json")
  if [ -z "$QUERY" ]; then
    echo "ERROR: VOICEVOX 未起動（audio_query failed）" >&2
    return 1
  fi
  curl -sf --connect-timeout 10 -X POST \
    "${VOICEVOX_URL}/synthesis?speaker=${SPEAKER}" \
    -H "Content-Type: application/json" \
    -d "$QUERY" \
    -o "$outfile"
  echo "generated: assets/initial_warning.wav"
  echo "  → git add assets/initial_warning.wav してコミットしてください"
}

echo "=== ずんだもん音声キャッシュ生成 ==="
echo "キャッシュ先: $CACHE_DIR"
echo ""

# ツール音声の生成
generate "PreToolUse_Bash"    "コマンドを実行するのだ"
generate "PreToolUse_Write"   "ファイルを書き込むのだ"
generate "PreToolUse_Edit"    "ファイルを編集するのだ"
generate "PreToolUse_Read"    "ファイルを読むのだ"
generate "PreToolUse_Glob"    "ファイルを探すのだ"
generate "PreToolUse_Grep"    "ファイルを検索するのだ"
generate "PostToolUse_Bash"   "コマンドが完了したのだ"
generate "PostToolUse_Write"  "書き込みが完了したのだ"
generate "PostToolUse_Edit"   "編集が完了したのだ"
generate "PreToolUse_Bash_GitPush"     "プッシュするのだ"
generate "PreToolUse_Bash_GhPrCreate"  "プルリクエストを作るのだ"
generate "PostToolUse_Bash_GitPush"    "プッシュが完了したのだ"
generate "PostToolUse_Bash_GhPrCreate" "プルリクエストを作ったのだ"

# 初回警告音声の生成（assets/ へ保存）
echo ""
generate_to_assets

echo ""
echo "=== 完了 ==="
ls -lh "$CACHE_DIR"/*.wav 2>/dev/null || echo "(WAVファイルなし)"
