// opencode-parakeet plugin — starts the local Parakeet server when OpenCode
// boots (cheaply: no model is loaded) and pre-warms the model when a recording
// starts, so transcription is instant when the recording ends. The server
// unloads the model right after each transcription.
//
// Installed by the opencode-parakeet installer into ~/.config/opencode/plugins/.
// https://github.com/moesuito/opencode-parakeet
//
// Configuration (all optional, environment variables win):
//   OPENCODE_PARAKEET_DIR        directory containing parakeet-server
//   OPENCODE_PARAKEET_PORT       port (default 8797)
//   OPENCODE_PARAKEET_MODEL      model file, absolute or relative to DIR
//   OPENCODE_PARAKEET_EAGER=1    load the model at server start (--preload)
//                                instead of on demand
//   OPENCODE_PARAKEET_DISABLE=1  disable this plugin
//   OPENCODE_PARAKEET_LOG        optional file to append plugin logs to
//
// The server is spawned detached (no console window on Windows) and keeps
// running when OpenCode exits; a quick probe prevents duplicate servers.

import { spawn } from "node:child_process"
import { appendFileSync, existsSync } from "node:fs"
import { isAbsolute, join } from "node:path"

const DEFAULTS = {
  dir: "__PARAKEET_DIR__",
  port: 8797,
  model: "tdt-0.6b-v3-f16.gguf",
}

function defaultDir(): string {
  const local = process.env.LOCALAPPDATA
  if (local) return join(local, "opencode-parakeet")
  const home = process.env.HOME ?? process.env.USERPROFILE ?? "."
  return join(home, ".opencode-parakeet")
}

function log(level: "info" | "warn", message: string) {
  const line = `[opencode-parakeet] ${message}`
  if (level === "warn") console.warn(line)
  else console.log(line)
  const file = process.env.OPENCODE_PARAKEET_LOG
  if (file) {
    try {
      appendFileSync(file, `[${new Date().toISOString()}] [${level}] ${line}\n`)
    } catch {}
  }
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function probe(port: number): Promise<"up" | "down" | "unverified"> {
  try {
    await fetch(`http://127.0.0.1:${port}/v1/audio/transcriptions`, { signal: AbortSignal.timeout(700) })
    return "up"
  } catch (error) {
    if (error instanceof Error && error.name === "TimeoutError") return "unverified"
    return "down"
  }
}

export default {
  id: "opencode-parakeet",
  async setup(ctx) {
    if (process.env.OPENCODE_PARAKEET_DISABLE === "1") return

    const port = Number(process.env.OPENCODE_PARAKEET_PORT ?? "") || DEFAULTS.port
    const dir = process.env.OPENCODE_PARAKEET_DIR || (DEFAULTS.dir.startsWith("__") ? defaultDir() : DEFAULTS.dir)
    const model = process.env.OPENCODE_PARAKEET_MODEL || DEFAULTS.model
    const eager = process.env.OPENCODE_PARAKEET_EAGER === "1"
    const server = join(dir, process.platform === "win32" ? "parakeet-server.exe" : "parakeet-server")
    const modelPath = isAbsolute(model) ? model : join(dir, model)

    async function startServer(): Promise<boolean> {
      const state = await probe(port)
      if (state === "up") return true
      if (state === "unverified") {
        log("warn", `port ${port} is occupied but did not answer; not starting a duplicate server`)
        return false
      }
      if (!existsSync(server)) {
        log("warn", `parakeet-server not found at ${server} - install it: https://github.com/moesuito/opencode-parakeet`)
        return false
      }
      if (!existsSync(modelPath)) {
        log("warn", `model not found at ${modelPath} - install it: https://github.com/moesuito/opencode-parakeet`)
        return false
      }
      log("info", `starting server on port ${port}${eager ? " (eager)" : ""}`)
      const args = ["--model", modelPath, "--port", String(port)]
      if (eager) args.push("--preload")
      const child = spawn(server, args, { cwd: dir, detached: true, stdio: "ignore", windowsHide: true })
      child.on("error", (error) => log("warn", `failed to start server: ${error.message}`))
      child.unref()
      for (let attempt = 0; attempt < 20; attempt++) {
        await sleep(250)
        if ((await probe(port)) !== "down") {
          log("info", `server ready on port ${port}`)
          return true
        }
      }
      log("warn", `server did not become ready on port ${port}`)
      return false
    }

    // Single-flight: a boot start and a recording event must not spawn twice.
    let starting: Promise<boolean> | null = null
    function ensureServer(): Promise<boolean> {
      if (!starting) {
        starting = startServer().finally(() => {
          starting = null
        })
      }
      return starting
    }

    // Pre-warm the model; if the server is down, bring it up and retry once.
    async function warmup(): Promise<void> {
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          const response = await fetch(`http://127.0.0.1:${port}/warmup`, {
            method: "POST",
            signal: AbortSignal.timeout(20_000),
          })
          if (response.ok) {
            log("info", `model warmed on port ${port}`)
            return
          }
          // An older server without /warmup loads its model eagerly; nothing to do.
          if (response.status === 404) return
          log("warn", `warmup returned ${response.status}`)
          return
        } catch {
          if (!(await ensureServer())) return
        }
      }
    }

    // Keep the cheap (model-less) server up while OpenCode runs.
    void ensureServer()

    // Pre-warm the model as soon as a recording starts, so the transcription
    // right after the recording does not pay the model load time.
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe()) {
          if (event.type === "voice.recording") void warmup()
        }
      } catch (error) {
        log("warn", `event subscription ended: ${error instanceof Error ? error.message : String(error)}`)
      }
    })()
  },
}
