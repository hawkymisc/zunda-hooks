#!/bin/bash
# セッション開始フック: VOICEVOX 起動 + セッション追跡 + 初回警告再生

CACHE_DIR="$HOME/.claude/hooks/zaudio"
SESSION_DIR="$CACHE_DIR/.sessions"
VOICEVOX_URL="http://localhost:50021"
VOICEVOX_BIN="$HOME/.voicevox/VOICEVOX.AppImage"
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

# 音声再生コマンドを選択
if command -v aplay >/dev/null 2>&1; then
  PLAYER="aplay -q"
elif command -v paplay >/dev/null 2>&1; then
  PLAYER="paplay"
else
  PLAYER=""
fi

# VOICEVOX が未起動なら起動
if ! curl -sf --connect-timeout 2 "${VOICEVOX_URL}/version" >/dev/null 2>&1; then
  if [ -f "$VOICEVOX_BIN" ]; then
    nohup "$VOICEVOX_BIN" --no-sandbox >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
    echo "zunda-session-start: VOICEVOX starting (PID $(cat "$PID_FILE"))" >&2
    # エンジンが応答するまで待機（最大30秒）
    for i in $(seq 1 30); do
      curl -sf --connect-timeout 1 "${VOICEVOX_URL}/version" >/dev/null 2>&1 && break
      sleep 1
    done
  else
    echo "zunda-session-start: VOICEVOX AppImage not found at $VOICEVOX_BIN" >&2
  fi
fi

# プレーヤーがなければ終了
[ -z "$PLAYER" ] && exit 0

# ツール音声 WAV の数を確認（initial_warning.wav は除く）
WAV_COUNT=$(find "$CACHE_DIR" -maxdepth 1 -type f -name "*.wav" 2>/dev/null | wc -l | tr -d ' ')

# キャッシュ未生成（初回）なら警告を再生
if [ "$WAV_COUNT" -eq 0 ] && [ -f "$INITIAL_WAV" ]; then
  $PLAYER "$INITIAL_WAV"  # 警告は同期再生（確実に聞かせる）
fi

exit 0
