#!/usr/bin/env bash
# Sends a prompt file to the model and prints the reply on stdout.
#
# With DIFFSUM_SERVER set (http://host:port) it talks to a model server that is
# already running. Otherwise it starts llamafile's server on loopback inside
# this container for the one request and stops it afterwards. The CLI mode of
# llamafile 0.10 ignores the switch that turns thinking off, the server's
# chat endpoint honours it, so both paths use the endpoint.
#
# Timings from the server are written as JSON to $DIFFSUM_WORKDIR/timings.json.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

[ $# -eq 1 ] || die "usage: run_model.sh PROMPT_FILE"
prompt=$1
work=${DIFFSUM_WORKDIR:-$(dirname "$prompt")}
max_tokens=${DIFFSUM_MAX_TOKENS:-300}

server=${DIFFSUM_SERVER:-}
load_seconds=null
peak_rss=null
server_pid=

stop_server() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
}
trap stop_server EXIT

if [ -z "$server" ]; then
    : "${LLAMAFILE:?LLAMAFILE is not set}" "${MODEL_GGUF:?MODEL_GGUF is not set}"
    port=${DIFFSUM_PORT:-8080}
    # About 2.5 bytes per token is pessimistic enough for code.
    ctx=$(($(wc -c <"$prompt") * 2 / 5 + max_tokens + 512))
    [ "$ctx" -ge 2048 ] || ctx=2048
    started=$(now)
    # llamafile is run through sh: exec'ing the file directly fails with
    # "not found" because the kernel has no loader for its header.
    sh "$LLAMAFILE" -m "$MODEL_GGUF" --server --host 127.0.0.1 --port "$port" \
        -c "$ctx" -np 1 --nologo --log-disable >/dev/null 2>&1 &
    server_pid=$!
    server=http://127.0.0.1:$port
    until curl -sf "$server/health" >/dev/null 2>&1; do
        kill -0 "$server_pid" 2>/dev/null || die "the model server exited during startup"
        sleep 0.25
    done
    load_seconds=$(elapsed "$started" "$(now)")
fi

jq -Rs --argjson max "$max_tokens" '{
        messages: [{role: "user", content: .}],
        temperature: 0, seed: 0, max_tokens: $max,
        cache_prompt: false,
        chat_template_kwargs: {enable_thinking: false}
    }' "$prompt" >"$work/request.json"

curl -sS --fail-with-body -m "${DIFFSUM_TIMEOUT:-900}" \
    -H 'Content-Type: application/json' \
    --data-binary @"$work/request.json" \
    "$server/v1/chat/completions" >"$work/response.json" ||
    die "model request failed: $(head -c 300 "$work/response.json" 2>/dev/null)"

# The weights are mapped, so the cgroup peak depends on which container touched
# the page cache first. The high-water RSS of the model process does not.
if [ -n "$server_pid" ]; then
    peak_rss=$(cat /proc/[0-9]*/status 2>/dev/null | awk '/^VmHWM:/ { if ($2 > m) m = $2 } END { print m * 1024 }')
fi

jq --argjson load "$load_seconds" --argjson rss "$peak_rss" \
    '{load_seconds: $load, peak_rss_bytes: $rss, prompt_tokens: .usage.prompt_tokens,
      completion_tokens: .usage.completion_tokens,
      prompt_ms: .timings.prompt_ms, generation_ms: .timings.predicted_ms}' \
    "$work/response.json" >"$work/timings.json"

jq -r '.choices[0].message.content' "$work/response.json" | sed -e 's/[[:space:]]*$//' -e '/./,$!d'
