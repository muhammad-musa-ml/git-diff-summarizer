#!/usr/bin/env bash
# Download the llamafile runtime and the Gemma GGUF into model/cache, resuming
# partial files and refusing anything whose SHA256 does not match the pins below.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cache=${1:-$here/cache}
mkdir -p "$cache"

runtime_url=https://github.com/mozilla-ai/llamafile/releases/download/0.10.6/llamafile-0.10.6
runtime_sha=d579f61dcd3a306f518e6d90e599d77793ed5f09543023d09c96ad35fcfa63f0
model_url=https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q5_K_M.gguf
model_sha=90293b8cdaf9c973012bf4df8a1e92bde7d74ad66a4fe56cf905ccd563d660c5

fetch() {
    local url=$1 sha=$2 out=$3
    if [ -f "$out" ] && [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$sha" ]; then
        echo "ok   $(basename "$out")"
        return
    fi
    local part=$out.part try
    for try in 1 2 3 4 5; do
        # -C - continues a partial download; the hosts send the real size on a 416
        if curl -fL --retry 3 -C - -o "$part" "$url"; then
            break
        fi
        echo "retry $try for $(basename "$out")" >&2
        sleep 3
    done
    got=$(sha256sum "$part" | cut -d' ' -f1)
    if [ "$got" != "$sha" ]; then
        echo "checksum mismatch for $(basename "$out"): got $got" >&2
        exit 1
    fi
    mv "$part" "$out"
    echo "got  $(basename "$out")"
}

fetch "$runtime_url" "$runtime_sha" "$cache/llamafile"
fetch "$model_url" "$model_sha" "$cache/model.gguf"
