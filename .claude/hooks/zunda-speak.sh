#!/bin/bash
# ずんだもん音声フックスクリプト（PreToolUse / PostToolUse 共用）

CACHE_DIR="$HOME/.claude/hooks/zaudio"
VOICEVOX_URL="http://localhost:50021"
SPEAKER=3

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

# テキストマッピング
build_text() {
  local event="$1" tool="$2"
  case "${event}_${tool}" in
    PreToolUse_Bash)   echo "コマンドを実行するのだ" ;;
    PreToolUse_Write)  echo "ファイルを書き込むのだ" ;;
    PreToolUse_Edit)   echo "ファイルを編集するのだ" ;;
    PreToolUse_Read)   echo "ファイルを読むのだ" ;;
    PreToolUse_Glob)   echo "ファイルを探すのだ" ;;
    PreToolUse_Grep)   echo "ファイルを検索するのだ" ;;
    PreToolUse_*)      echo "${tool}を使うのだ" ;;
    PostToolUse_Bash)  echo "コマンドが完了したのだ" ;;
    PostToolUse_Write) echo "書き込みが完了したのだ" ;;
    PostToolUse_Edit)  echo "編集が完了したのだ" ;;
    PostToolUse_*)     echo "${tool}が完了したのだ" ;;
    *) echo "" ;;
  esac
}

TEXT=$(build_text "$EVENT" "$TOOL")
[ -z "$TEXT" ] && exit 0

mkdir -p "$CACHE_DIR"
CACHE_KEY="${EVENT}_${TOOL}"
CACHE_FILE="$CACHE_DIR/${CACHE_KEY}.wav"

# 音声再生コマンドを選択
if command -v aplay >/dev/null 2>&1; then
  PLAYER="aplay -q"
elif command -v paplay >/dev/null 2>&1; then
  PLAYER="paplay"
else
  echo "zunda-speak: no audio player found (aplay/paplay)" >&2
  exit 0
fi

# キャッシュヒット → 即再生
if [ -f "$CACHE_FILE" ]; then
  $PLAYER "$CACHE_FILE" &
  exit 0
fi

# キャッシュミス → VOICEVOX で合成してキャッシュ保存
ENCODED_TEXT=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$TEXT")
QUERY=$(curl -sf --connect-timeout 3 -X POST \
  "${VOICEVOX_URL}/audio_query?text=${ENCODED_TEXT}&speaker=${SPEAKER}" \
  -H "Content-Type: application/json")

[ -z "$QUERY" ] && exit 0  # VOICEVOX 未起動時はサイレント終了

curl -sf --connect-timeout 10 -X POST \
  "${VOICEVOX_URL}/synthesis?speaker=${SPEAKER}" \
  -H "Content-Type: application/json" \
  -d "$QUERY" \
  -o "$CACHE_FILE"

[ -f "$CACHE_FILE" ] && $PLAYER "$CACHE_FILE" &
exit 0
