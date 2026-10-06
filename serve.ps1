#!/usr/bin/env pwsh
# Starts a local Parakeet server for OpenCode voice input.
# Binaries: https://github.com/mudler/parakeet.cpp/releases
# Models:   https://huggingface.co/mudler/parakeet-cpp-gguf
#
# Usage: ./serve.ps1 [-Server <path>] [-Model <path>] [-Port 8797]
param(
  [string]$Server = "$PSScriptRoot\parakeet-server.exe",
  [string]$Model  = "$PSScriptRoot\tdt-0.6b-v3-f16.gguf",
  [int]$Port = 8797
)

if (-not (Test-Path $Server)) {
  Write-Error "parakeet-server not found at '$Server'. Download a release: https://github.com/mudler/parakeet.cpp/releases"
  exit 1
}
if (-not (Test-Path $Model)) {
  Write-Error "model not found at '$Model'. Download a GGUF: https://huggingface.co/mudler/parakeet-cpp-gguf"
  exit 1
}

Write-Host "Serving Parakeet on http://127.0.0.1:$Port (OpenAI-compatible /v1/audio/transcriptions)"
& $Server --model $Model --port $Port
