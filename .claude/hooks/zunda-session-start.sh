#!/bin/bash
# セッション開始フック: VOICEVOX 起動 + セッション追跡 + 初回警告再生

CACHE_DIR="$HOME/.claude/hooks/zaudio"
SESSION_DIR="$CACHE_DIR/.sessions"
VOICEVOX_URL="http://localhost:50021"
PID_FILE="$CACHE_DIR/.voicevox.pid"

# CLAUDE_PROJECT_DIR 未定義ガード
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  echo "zunda-session-start: CLAUDE_PROJECT_DIR unset, skipping" >&2
  exit 0
fi

INITIAL_WAV="${CLAUDE_PROJECT_DIR}/assets/initial_warning.wav"

mkdir -p "$CACHE_DIR" "$SESSION_DIR"

# セッション PID ファイルを作成
SESSION_ID=$(echo "${CLAUDE_SESSION_ID:-$$}" | tr -cd '[:alnum:]_-')
[ -n "$SESSION_ID" ] && touch "$SESSION_DIR/$SESSION_ID"

# OS 判定
OS=$(uname -s)

# OS 別: VOICEVOX バイナリパス
case "$OS" in
  Linux*)
    VOICEVOX_BIN="$HOME/.voicevox/VOICEVOX.AppImage"
    VOICEVOX_LAUNCH_OPTS="--no-sandbox"
    ;;
  Darwin*)
    VOICEVOX_BIN="/Applications/VOICEVOX.app/Contents/MacOS/VOICEVOX"
    VOICEVOX_LAUNCH_OPTS=""
    ;;
  MINGW*|MSYS*|CYGWIN*)
    # Git Bash / MSYS2 / Cygwin on Windows
    if [ -z "${LOCALAPPDATA:-}" ]; then
      echo "zunda-session-start: LOCALAPPDATA is not set; cannot locate VOICEVOX on Windows" >&2
      VOICEVOX_BIN=""
    else
      VOICEVOX_BIN="${LOCALAPPDATA}/Programs/VOICEVOX/VOICEVOX.exe"
    fi
    VOICEVOX_LAUNCH_OPTS=""
    ;;
  *)
    VOICEVOX_BIN=""
    VOICEVOX_LAUNCH_OPTS=""
    ;;
esac

# OS 別: WAV 再生関数
play_wav() {
  local file="$1"
  [ -f "$file" ] || return
  case "$OS" in
    Darwin*)
      afplay "$file" ;;
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
        "(New-Object Media.SoundPlayer '$escaped').PlaySync()" 2>/dev/null ;;
    *)
      if command -v aplay >/dev/null 2>&1; then
        aplay -q "$file"
      elif command -v paplay >/dev/null 2>&1; then
        paplay "$file"
      fi ;;
  esac
}

# キャッシュマニフェストに記載された全ファイルが存在するか確認
# マニフェストは pregenerate.sh 実行時に生成される
# 注意: キャッシュ完備でも未知のツール名はリアルタイム合成が必要なため、
#       VOICEVOX を使いたい場合は手動で起動するか pregenerate.sh を再実行してください
CACHE_MANIFEST="$CACHE_DIR/.cache-manifest"
ALL_CACHED=false
if [ -f "$CACHE_MANIFEST" ]; then
  ALL_CACHED=true
  while IFS= read -r key || [ -n "$key" ]; do
    [ -n "$key" ] || continue
    if [ ! -s "$CACHE_DIR/${key}.wav" ]; then
      ALL_CACHED=false
      break
    fi
  done < "$CACHE_MANIFEST"
fi

# VOICEVOX が未起動なら起動（マニフェスト記載のキャッシュが全て揃っている場合はスキップ）
if [ "$ALL_CACHED" = "false" ] && ! curl -sf --connect-timeout 2 "${VOICEVOX_URL}/version" >/dev/null 2>&1; then
  if [ -n "$VOICEVOX_BIN" ] && [ -f "$VOICEVOX_BIN" ]; then
    # shellcheck disable=SC2086
    nohup "$VOICEVOX_BIN" $VOICEVOX_LAUNCH_OPTS >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
    echo "zunda-session-start: VOICEVOX starting (PID $(cat "$PID_FILE"))" >&2
    # エンジンが応答するまで待機（最大30秒）
    for i in $(seq 1 30); do
      curl -sf --connect-timeout 1 "${VOICEVOX_URL}/version" >/dev/null 2>&1 && break
      sleep 1
    done
  else
    echo "zunda-session-start: VOICEVOX not found at $VOICEVOX_BIN" >&2
  fi
fi

# ツール音声 WAV の存在確認（キャッシュ未生成なら警告再生）
if ! find "$CACHE_DIR" -maxdepth 1 -type f -name "*.wav" -print -quit 2>/dev/null | grep -q .; then
  play_wav "$INITIAL_WAV"  # 警告は同期再生（確実に聞かせる）
fi

exit 0
