# opencode-parakeet

Local, OpenAI-compatible speech-to-text for [OpenCode](https://github.com/anomalyco/opencode) voice input — powered by NVIDIA **Parakeet TDT 0.6B v3** via [parakeet.cpp](https://github.com/mudler/parakeet.cpp) (GGML + Vulkan/CPU). Everything runs on your machine: no cloud, no API keys, very low latency.

> Setup used to test [feat: voice input for the terminal and web clients (opencode#53492)](https://github.com/anomalyco/opencode/pull/53492).

[![release](https://img.shields.io/github/v/release/moesuito/opencode-parakeet)](https://github.com/moesuito/opencode-parakeet/releases) [![license](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

| Audio | Transcribe time | Hardware |
| ----- | --------------- | -------- |
| 6.6 s | ~110 ms (~60× realtime) | AMD Radeon RX 9060 XT (Vulkan), Windows 11 |

## Why

OpenCode can dictate (TUI `Ctrl+Y`, mic button in the web/desktop composer) by POSTing recordings to any OpenAI-compatible `audio/transcriptions` endpoint. Pointing that at a local Parakeet server gives you fast, private dictation.

## Install (Windows)

One command in PowerShell **5.1 or 7+** — downloads the server runtime, verifies its checksum, downloads a model from Hugging Face, generates a `serve.ps1` launcher and installs the OpenCode plugin that starts it automatically:

```powershell
irm https://raw.githubusercontent.com/moesuito/opencode-parakeet/main/install.ps1 | iex
```

Need options? Use a script block:

```powershell
$s = irm https://raw.githubusercontent.com/moesuito/opencode-parakeet/main/install.ps1
& ([scriptblock]::Create($s)) -Backend cpu -Model q8_0 -Configure
```

| Option | Default | Description |
| ------ | ------- | ----------- |
| `-Backend vulkan\|cpu` | `vulkan` | GPU (Vulkan) or CPU-only build |
| `-Model f16\|q8_0\|q6_k\|q5_k\|q4_k` | `f16` | Model size/quality/speed trade-off |
| `-InstallDir <path>` | `%LOCALAPPDATA%\opencode-parakeet` | Where everything is installed |
| `-Port <n>` | `8797` | Port used by the generated launcher |
| `-Configure` | off | Adds the `voice` block to `~/.config/opencode/cli.json` and `opencode.json` (with backups) |
| `-NoPlugin` | off | Skip installing the OpenCode plugin |
| `-NoModel` / `-NoVerify` / `-Force` | — | Skip model download / skip checksums / reinstall |

The installer verifies the server's SHA256 against `SHA256SUMS` and the model's SHA256 against the hash advertised by Hugging Face; the model download resumes if interrupted.

## Configure OpenCode

Voice input stays disabled until `voice.url` is set. Add this to:

- TUI: `~/.config/opencode/cli.json`
- web/desktop: `~/.config/opencode/opencode.json`

```json
{
  "voice": {
    "url": "http://127.0.0.1:8797/v1/audio/transcriptions",
    "model": "parakeet"
  }
}
```

`apiKey` is only needed for cloud endpoints. Or just re-run the installer with `-Configure`.

## Auto-start with OpenCode (plugin)

The installer drops a small OpenCode plugin at `~/.config/opencode/plugins/opencode-parakeet.ts`. On every OpenCode boot the plugin:

- probes `http://127.0.0.1:<port>` and does nothing if a server is already listening (no duplicates),
- otherwise starts `parakeet-server` detached (no console window) with a model, so voice input is ready.

Environment overrides (all optional):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `OPENCODE_PARAKEET_DIR` | install dir | directory containing `parakeet-server` |
| `OPENCODE_PARAKEET_PORT` | `8797` | port to check/start |
| `OPENCODE_PARAKEET_MODEL` | `tdt-0.6b-v3-f16.gguf` | model file (absolute or relative to `DIR`) |
| `OPENCODE_PARAKEET_DISABLE` | — | set to `1` to disable the plugin |
| `OPENCODE_PARAKEET_LOG` | — | append plugin logs to a file |

Manual setup: copy [`plugin/opencode-parakeet.ts`](./plugin/opencode-parakeet.ts) into `~/.config/opencode/plugins/` and adjust its `DEFAULTS` block.

## Run the server

```powershell
& "$env:LOCALAPPDATA\opencode-parakeet\serve.ps1"
```

Or manually, with any [parakeet.cpp](https://github.com/mudler/parakeet.cpp/releases) build (Linux/macOS too):

```bash
./parakeet-server --model ./tdt-0.6b-v3-f16.gguf --port 8797
```

`serve.sh` in this repo wraps that for Linux/macOS.

## Use it

- **TUI**: `Ctrl+Y` records, press again (or Enter) to stop and send; `Alt+Y` inserts the transcription without sending.
- **Web/desktop**: click the mic in the composer; the composer's send button stops the recording, transcribes, appends it to what you already typed and sends.

## Test the server directly

```bash
curl http://127.0.0.1:8797/v1/audio/transcriptions \
  -F "file=@sample-16k-mono.wav" \
  -F "model=parakeet"
# {"text":"..."}
```

Recordings should be WAV (16 kHz mono recommended) — OpenCode's recorder already uploads in exactly this format.

## Releases

This repository mirrors the latest [parakeet.cpp](https://github.com/mudler/parakeet.cpp) release **with binaries**, pinned and checksummed:

- `parakeet-server-win-x64-vulkan.zip` — GPU build (Vulkan)
- `parakeet-server-win-x64-cpu.zip` — CPU-only build
- `SHA256SUMS`

Both are byte-identical to the corresponding upstream assets (currently parakeet.cpp v0.5.0). Other platforms/backends (Linux, macOS, CUDA): grab them from the [upstream releases](https://github.com/mudler/parakeet.cpp/releases).

## Troubleshooting

- **Server exits immediately on the Vulkan build** — your GPU/driver may not support Vulkan. Re-run the installer with `-Backend cpu`.
- **Port already in use** — pass another port to `serve.ps1` (`-Port 8798`) and update `voice.url`.
- **First request is slow** — the model is loaded into memory on first use.

## Notes

- Works with any OpenAI-compatible transcription server (e.g. `whisper.cpp`'s `whisper-server`) — Parakeet is just very fast and light.
- Third-party binaries and model weights are downloaded from their official sources; this repo only ships docs, scripts and checksummed mirrors.

## Credits

- [mudler/parakeet.cpp](https://github.com/mudler/parakeet.cpp) — MIT, by the [LocalAI](https://github.com/mudler/LocalAI) team (ggml-based Parakeet inference).
- NVIDIA [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — model weights ([GGUF builds](https://huggingface.co/mudler/parakeet-cpp-gguf)).

## License

MIT — see [LICENSE](./LICENSE).
