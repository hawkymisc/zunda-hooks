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
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# キャッシュが 0 件なら初回警告音声を再生（同期）
# BASH_SOURCE[0] でスクリプト自身のパスを確実に解決（PATH 経由の起動でも正しく動作する）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INITIAL_WAV="${SCRIPT_DIR}/assets/initial_warning.wav"
if ! find "$CACHE_DIR" -maxdepth 1 -type f -name "*.wav" -print -quit 2>/dev/null | grep -q .; then
  if [ -f "$INITIAL_WAV" ]; then
    if command -v aplay >/dev/null 2>&1; then
      aplay -q "$INITIAL_WAV"
    elif command -v paplay >/dev/null 2>&1; then
      paplay "$INITIAL_WAV"
    fi
  fi
fi

# ツール音声マップ（キー:テキスト）— ここが唯一の正とする
# generate() 呼び出しとキャッシュマニフェストの両方をこの配列から生成するため、
# 新しいキーを追加する際はここだけ変更すればよい
TOOL_AUDIO_MAP=(
  "PreToolUse_Bash:コマンドを実行するのだ"
  "PreToolUse_Write:ファイルを書き込むのだ"
  "PreToolUse_Edit:ファイルを編集するのだ"
  "PreToolUse_Read:ファイルを読むのだ"
  "PreToolUse_Glob:ファイルを探すのだ"
  "PreToolUse_Grep:ファイルを検索するのだ"
  "PostToolUse_Bash:コマンドが完了したのだ"
  "PostToolUse_Write:書き込みが完了したのだ"
  "PostToolUse_Edit:編集が完了したのだ"
  "PreToolUse_Bash_GitPush:プッシュするのだ"
  "PreToolUse_Bash_GhPrCreate:プルリクエストを作るのだ"
  "PostToolUse_Bash_GitPush:プッシュが完了したのだ"
  "PostToolUse_Bash_GhPrCreate:プルリクエストを作ったのだ"
)

# ツール音声の生成
for entry in "${TOOL_AUDIO_MAP[@]}"; do
  key="${entry%%:*}"
  text="${entry#*:}"
  generate "$key" "$text"
done

# 初回警告音声の生成（assets/ へ保存）
echo ""
generate_to_assets

# キャッシュマニフェストを更新（zunda-session-start.sh がキャッシュ完備を判断するために使用）
# TOOL_AUDIO_MAP からキーのみを抽出して書き出す（generate_to_assets は対象外）
{
  for entry in "${TOOL_AUDIO_MAP[@]}"; do
    printf '%s\n' "${entry%%:*}"
  done
} > "$CACHE_DIR/.cache-manifest"
echo "updated: .cache-manifest"

echo ""
echo "=== 完了 ==="
ls -lh "$CACHE_DIR"/*.wav 2>/dev/null || echo "(WAVファイルなし)"
