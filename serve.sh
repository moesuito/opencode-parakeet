#!/usr/bin/env bash
# Starts a local Parakeet server for OpenCode voice input.
# Binaries: https://github.com/mudler/parakeet.cpp/releases
# Models:   https://huggingface.co/mudler/parakeet-cpp-gguf
#
# Usage: ./serve.sh [server-bin] [model-gguf] [port]
set -e

SERVER="${1:-./parakeet-server}"
MODEL="${2:-./tdt-0.6b-v3-f16.gguf}"
PORT="${3:-8797}"

if [ ! -x "$SERVER" ]; then
  echo "parakeet-server not found or not executable at '$SERVER'."
  echo "Download a release: https://github.com/mudler/parakeet.cpp/releases"
  exit 1
fi
if [ ! -f "$MODEL" ]; then
  echo "model not found at '$MODEL'."
  echo "Download a GGUF: https://huggingface.co/mudler/parakeet-cpp-gguf"
  exit 1
fi

echo "Serving Parakeet on http://127.0.0.1:$PORT (OpenAI-compatible /v1/audio/transcriptions)"
exec "$SERVER" --model "$MODEL" --port "$PORT"
