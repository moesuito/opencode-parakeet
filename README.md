# opencode-parakeet

Local, OpenAI-compatible speech-to-text for [OpenCode](https://github.com/anomalyco/opencode) voice input — powered by NVIDIA **Parakeet TDT 0.6B v3** via [parakeet.cpp](https://github.com/mudler/parakeet.cpp) (GGML + Vulkan). Everything runs on your machine: no cloud, no API keys, very low latency.

> Setup used to test [feat: voice input for the terminal and web clients (opencode#53492)](https://github.com/anomalyco/opencode/pull/53492).

## Why

OpenCode can dictate (TUI `Ctrl+Y`, mic button in the web/desktop composer) by POSTing recordings to any OpenAI-compatible `audio/transcriptions` endpoint. Pointing that at a local Parakeet server gives you fast, private dictation:

| Audio | Transcribe time | Hardware |
| ----- | --------------- | -------- |
| 6.6 s | ~110 ms (~60× realtime) | AMD Radeon RX 9060 XT (Vulkan), Windows 11 |

CPU-only builds work as well (slower).

## Quick start

1. **Get parakeet.cpp** — grab a prebuilt release from [mudler/parakeet.cpp](https://github.com/mudler/parakeet.cpp) (e.g. `parakeet-v0.5.0-bin-win-vulkan-x64.zip` for Windows + Vulkan), or build from source.
2. **Get a model** — from [mudler/parakeet-cpp-gguf](https://huggingface.co/mudler/parakeet-cpp-gguf):
   - `tdt-0.6b-v3-f16.gguf` (~1.4 GB, best quality) — used here
   - `tdt-0.6b-v3-q8_0.gguf` (~0.9 GB, smaller)
3. **Run the server**:

   ```powershell
   .\parakeet-server.exe --model .\tdt-0.6b-v3-f16.gguf --port 8797
   ```

   or use `serve.ps1` (Windows) / `serve.sh` (Linux/macOS) from this repo.

4. **Configure OpenCode** — add a `voice` block to your config:
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

   `apiKey` is only needed for cloud endpoints. Voice input stays disabled until `url` is set.

5. **Use it** — TUI: `Ctrl+Y` records, then send on stop; `Alt+Y` inserts the transcription without sending. Web: click the mic in the composer.

## Test the server directly

```bash
curl http://127.0.0.1:8797/v1/audio/transcriptions \
  -F "file=@sample-16k-mono.wav" \
  -F "model=parakeet"
# {"text":"..."}
```

Recordings should be WAV (16 kHz mono recommended). OpenCode's recorder already uploads in exactly this format.

## Notes

- Works with any OpenAI-compatible transcription server (e.g. `whisper.cpp`'s `whisper-server`) — Parakeet is just very fast and light.
- The server binary and model weights are third-party downloads; this repo only ships docs and helper scripts.

## Credits

- [mudler/parakeet.cpp](https://github.com/mudler/parakeet.cpp) — MIT, by the [LocalAI](https://github.com/mudler/LocalAI) team (ggml-based Parakeet inference).
- NVIDIA [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — model weights.

## License

MIT — see [LICENSE](./LICENSE).
