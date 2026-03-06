#!/bin/bash
# セッション終了フック: セッション追跡削除 + 最後のセッションなら VOICEVOX 終了

CACHE_DIR="$HOME/.claude/hooks/zaudio"
SESSION_DIR="$CACHE_DIR/.sessions"
PID_FILE="$CACHE_DIR/.voicevox.pid"

# セッション PID ファイルを削除
SESSION_ID=$(echo "${CLAUDE_SESSION_ID:-}" | tr -cd '[:alnum:]_-')
if [ -n "$SESSION_ID" ]; then
  rm -f "$SESSION_DIR/$SESSION_ID"
fi

# 残存セッション数を確認
REMAINING=$(find "$SESSION_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')

# 残存 0 件 → VOICEVOX を終了
if [ "$REMAINING" -eq 0 ] && [ -f "$PID_FILE" ]; then
  VOICEVOX_PID=$(cat "$PID_FILE")
  if [ -n "$VOICEVOX_PID" ]; then
    kill "$VOICEVOX_PID" 2>/dev/null || true
    echo "zunda-session-end: VOICEVOX terminated (PID $VOICEVOX_PID)" >&2
  fi
  rm -f "$PID_FILE"
fi

exit 0
