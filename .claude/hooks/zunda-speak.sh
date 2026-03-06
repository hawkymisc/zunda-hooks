#!/bin/bash
# ずんだもん音声フックスクリプト（PreToolUse / PostToolUse 共用）

CACHE_DIR="$HOME/.claude/hooks/zaudio"
VOICEVOX_URL="http://localhost:50021"
SPEAKER=3

# 依存コマンド早期チェック
if ! command -v jq >/dev/null 2>&1; then
  echo "zunda-speak: jq not found. Install: sudo apt install jq" >&2
  exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "zunda-speak: python3 not found." >&2
  exit 0
fi

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Bash ツールのコマンド内容を取得（git push / gh pr create 検出用）
BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# テキストとキャッシュキーのマッピング
# 戻り値: "TEXT\tCACHE_KEY"（タブ区切り）
resolve() {
  local event="$1" tool="$2" cmd="$3"
  # Bash の場合はコマンド内容で細分化
  if [ "$event" = "PreToolUse" ] && [ "$tool" = "Bash" ]; then
    if echo "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]|$)'; then
      printf '%s\t%s' "プッシュするのだ" "PreToolUse_Bash_GitPush"
      return
    fi
    if echo "$cmd" | grep -qE '(^|[;&|[:space:]])(gh[[:space:]]+pr[[:space:]]+create)([[:space:]]|$)'; then
      printf '%s\t%s' "プルリクエストを作るのだ" "PreToolUse_Bash_GhPrCreate"
      return
    fi
  fi
  if [ "$event" = "PostToolUse" ] && [ "$tool" = "Bash" ]; then
    PREV_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
    if echo "$PREV_CMD" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]|$)'; then
      printf '%s\t%s' "プッシュが完了したのだ" "PostToolUse_Bash_GitPush"
      return
    fi
    if echo "$PREV_CMD" | grep -qE '(^|[;&|[:space:]])(gh[[:space:]]+pr[[:space:]]+create)([[:space:]]|$)'; then
      printf '%s\t%s' "プルリクエストを作ったのだ" "PostToolUse_Bash_GhPrCreate"
      return
    fi
  fi
  # デフォルトマッピング
  case "${event}_${tool}" in
    PreToolUse_Bash)   printf '%s\t%s' "コマンドを実行するのだ"  "PreToolUse_Bash" ;;
    PreToolUse_Write)  printf '%s\t%s' "ファイルを書き込むのだ"  "PreToolUse_Write" ;;
    PreToolUse_Edit)   printf '%s\t%s' "ファイルを編集するのだ"  "PreToolUse_Edit" ;;
    PreToolUse_Read)   printf '%s\t%s' "ファイルを読むのだ"      "PreToolUse_Read" ;;
    PreToolUse_Glob)   printf '%s\t%s' "ファイルを探すのだ"      "PreToolUse_Glob" ;;
    PreToolUse_Grep)   printf '%s\t%s' "ファイルを検索するのだ"  "PreToolUse_Grep" ;;
    PreToolUse_*)      printf '%s\t%s' "${tool}を使うのだ"       "PreToolUse_${tool}" ;;
    PostToolUse_Bash)  printf '%s\t%s' "コマンドが完了したのだ"  "PostToolUse_Bash" ;;
    PostToolUse_Write) printf '%s\t%s' "書き込みが完了したのだ"  "PostToolUse_Write" ;;
    PostToolUse_Edit)  printf '%s\t%s' "編集が完了したのだ"      "PostToolUse_Edit" ;;
    PostToolUse_*)     printf '%s\t%s' "${tool}が完了したのだ"   "PostToolUse_${tool}" ;;
    *)                 printf '%s\t%s' "" "" ;;
  esac
}

RESOLVED=$(resolve "$EVENT" "$TOOL" "$BASH_CMD")
TEXT=$(echo "$RESOLVED" | cut -f1)
CACHE_KEY=$(echo "$RESOLVED" | cut -f2)

[ -z "$TEXT" ] && exit 0

mkdir -p "$CACHE_DIR"

# パストラバーサル防止: キャッシュキーを英数字・アンダースコアのみに制限
SAFE_KEY=$(echo "$CACHE_KEY" | tr -cd '[:alnum:]_')
CACHE_FILE="$CACHE_DIR/${SAFE_KEY}.wav"

# OS 別: WAV 再生関数（バックグラウンド再生）
OS=$(uname -s)
play_wav_bg() {
  local file="$1"
  [ -f "$file" ] || return
  case "$OS" in
    Darwin*)
      afplay "$file" & ;;
    MINGW*|MSYS*|CYGWIN*)
      local winpath
      winpath=$(cygpath -w "$file" 2>/dev/null || echo "$file")
      powershell.exe -NoProfile -Command \
        "(New-Object Media.SoundPlayer '$winpath').PlaySync()" 2>/dev/null & ;;
    *)
      if command -v aplay >/dev/null 2>&1; then
        aplay -q "$file" &
      elif command -v paplay >/dev/null 2>&1; then
        paplay "$file" &
      else
        echo "zunda-speak: no audio player found (aplay/paplay/afplay)" >&2
      fi ;;
  esac
}

# キャッシュヒット → 即再生（0バイトファイルは無効として削除）
if [ -f "$CACHE_FILE" ]; then
  if [ ! -s "$CACHE_FILE" ]; then
    rm -f "$CACHE_FILE"
  else
    play_wav_bg "$CACHE_FILE"
    exit 0
  fi
fi

# キャッシュミス → VOICEVOX で合成してキャッシュ保存（atomic write）
ENCODED_TEXT=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$TEXT")
QUERY=$(curl -sf --connect-timeout 3 -X POST \
  "${VOICEVOX_URL}/audio_query?text=${ENCODED_TEXT}&speaker=${SPEAKER}" \
  -H "Content-Type: application/json")

[ -z "$QUERY" ] && exit 0  # VOICEVOX 未起動時はサイレント終了

# 一時ファイルに書き込んでから atomic rename（レースコンディション対策）
TMP_FILE=$(mktemp "${CACHE_DIR}/.tmp_XXXXXX.wav")
curl -sf --connect-timeout 10 -X POST \
  "${VOICEVOX_URL}/synthesis?speaker=${SPEAKER}" \
  -H "Content-Type: application/json" \
  -d "$QUERY" \
  -o "$TMP_FILE"

# 正常なサイズか確認してからキャッシュに配置
if [ -s "$TMP_FILE" ]; then
  mv "$TMP_FILE" "$CACHE_FILE"
  play_wav_bg "$CACHE_FILE"
else
  rm -f "$TMP_FILE"
fi

exit 0
