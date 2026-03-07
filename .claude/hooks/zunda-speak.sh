#!/bin/bash
# ずんだもん音声フックスクリプト（PreToolUse / PostToolUse 共用）

CACHE_DIR="$HOME/.claude/hooks/zaudio"
LOCK_FILE="$CACHE_DIR/.playing.lock"
PID_FILE="$CACHE_DIR/.voicevox.pid"
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

# ヘルパー: ロックが有効か確認（PID 生存 + プロセス名による PID 再利用チェック）
_lock_is_active() {
  [ -f "$LOCK_FILE" ] || return 1
  local pid
  pid=$(cat "$LOCK_FILE" 2>/dev/null) || return 1
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  # PID 再利用チェック: プロセス名が音声プレイヤーか確認
  local comm
  comm=$(ps -p "$pid" -o comm= 2>/dev/null) || return 1
  echo "$comm" | grep -qiE '^(afplay|aplay|paplay|powershell|POWERSHELL\.EXE)$'
}

# 早期チェック（高速パス: 明らかに再生中の場合のみスキップ）
if _lock_is_active; then
  exit 0
fi
rm -f "$LOCK_FILE"

# OS 別: WAV 再生関数（再生直前にアトミックなロック取得 + バックグラウンド再生）
OS=$(uname -s)
play_wav_bg() {
  local file="$1"
  [ -f "$file" ] || return
  # TOCTOU 対策: noclobber でアトミックなロック取得を試みる
  # 別フックが合成中にここへ到達した場合の競合を防止
  if ! (set -o noclobber; : > "$LOCK_FILE") 2>/dev/null; then
    if _lock_is_active; then
      return  # 本当に再生中 → スキップ
    fi
    # 孤児ロック → 強制削除して再取得
    rm -f "$LOCK_FILE"
    (set -o noclobber; : > "$LOCK_FILE") 2>/dev/null || return
  fi
  case "$OS" in
    Darwin*)
      afplay "$file" &
      echo $! > "$LOCK_FILE" ;;
    MINGW*|MSYS*|CYGWIN*)
      local winpath
      if command -v cygpath >/dev/null 2>&1; then
        winpath=$(cygpath -w "$file")
      else
        # cygpath 不在時: /c/Users/... 形式を c:\Users\... 形式に手動変換
        winpath=$(printf '%s' "$file" | sed 's|^/\([a-zA-Z]\)/|\1:/|;s|/|\\|g')
      fi
      # シングルクォートをエスケープ（PowerShell インジェクション防止）
      local escaped="${winpath//\'/\'\'}"
      powershell.exe -NoProfile -Command \
        "(New-Object Media.SoundPlayer '$escaped').PlaySync()" 2>/dev/null &
      echo $! > "$LOCK_FILE" ;;
    *)
      if command -v aplay >/dev/null 2>&1; then
        aplay -q "$file" &
        echo $! > "$LOCK_FILE"
      elif command -v paplay >/dev/null 2>&1; then
        paplay "$file" &
        echo $! > "$LOCK_FILE"
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

# キャッシュミス → VOICEVOX が未起動ならオンデマンド起動
if ! curl -sf --connect-timeout 1 "${VOICEVOX_URL}/version" >/dev/null 2>&1; then
  # OS別バイナリパスを解決
  case "$OS" in
    Linux*)
      VOICEVOX_BIN="$HOME/.voicevox/VOICEVOX.AppImage"
      VOICEVOX_LAUNCH_OPTS="--no-sandbox" ;;
    Darwin*)
      VOICEVOX_BIN="/Applications/VOICEVOX.app/Contents/MacOS/VOICEVOX"
      VOICEVOX_LAUNCH_OPTS="" ;;
    MINGW*|MSYS*|CYGWIN*)
      if [ -n "${LOCALAPPDATA:-}" ]; then
        VOICEVOX_BIN="${LOCALAPPDATA}/Programs/VOICEVOX/VOICEVOX.exe"
      else
        VOICEVOX_BIN=""
      fi
      VOICEVOX_LAUNCH_OPTS="" ;;
    *)
      VOICEVOX_BIN=""
      VOICEVOX_LAUNCH_OPTS="" ;;
  esac

  # 起動ロック（noclobber）で排他制御: 1プロセスだけが起動担当となり他は待機
  START_LOCK="$CACHE_DIR/.voicevox.starting"
  if (set -o noclobber; : > "$START_LOCK") 2>/dev/null; then
    # クラッシュ時のロックリーク防止: EXIT で必ずロックを解放する
    trap 'rm -f "$START_LOCK"' EXIT
    # 起動ロック取得成功 → 自分がVOICEVOX起動担当
    if [ -n "$VOICEVOX_BIN" ] && [ -f "$VOICEVOX_BIN" ]; then
      # shellcheck disable=SC2086
      nohup "$VOICEVOX_BIN" $VOICEVOX_LAUNCH_OPTS >/dev/null 2>&1 &
      echo $! > "$PID_FILE"
      # エンジンが応答するまで待機（最大30秒）
      started=false
      for i in $(seq 1 30); do
        if curl -sf --connect-timeout 1 "${VOICEVOX_URL}/version" >/dev/null 2>&1; then
          started=true
          break
        fi
        sleep 1
      done
      [ "$started" = "false" ] && echo "zunda-speak: VOICEVOX did not respond within 30s" >&2
    else
      echo "zunda-speak: VOICEVOX not found at ${VOICEVOX_BIN:-(unknown)}" >&2
    fi
    rm -f "$START_LOCK"
    trap - EXIT  # ロック解放済みなので EXIT トラップをリセット（他プロセスのロックを消さないため）
  else
    # 他プロセスが起動中 → 応答が来るまで待機（最大30秒）
    waited=false
    for i in $(seq 1 30); do
      if curl -sf --connect-timeout 1 "${VOICEVOX_URL}/version" >/dev/null 2>&1; then
        waited=true
        break
      fi
      sleep 1
    done
    [ "$waited" = "false" ] && echo "zunda-speak: timed out waiting for VOICEVOX" >&2
  fi
fi

# VOICEVOX で合成してキャッシュ保存（atomic write）
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
