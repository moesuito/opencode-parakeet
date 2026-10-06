// opencode-parakeet plugin — starts the local Parakeet speech-to-text server
// whenever OpenCode boots, unless a server is already listening.
//
// Installed by the opencode-parakeet installer into ~/.config/opencode/plugins/.
// https://github.com/moesuito/opencode-parakeet
//
// Configuration (all optional, environment variables win):
//   OPENCODE_PARAKEET_DIR      directory containing parakeet-server
//   OPENCODE_PARAKEET_PORT     port (default 8797)
//   OPENCODE_PARAKEET_MODEL    model file, absolute or relative to DIR
//   OPENCODE_PARAKEET_DISABLE  set to 1 to disable this plugin
//   OPENCODE_PARAKEET_LOG      optional file to append plugin logs to
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
  async setup() {
    if (process.env.OPENCODE_PARAKEET_DISABLE === "1") return

    const port = Number(process.env.OPENCODE_PARAKEET_PORT ?? "") || DEFAULTS.port
    const dir = process.env.OPENCODE_PARAKEET_DIR || (DEFAULTS.dir.startsWith("__") ? defaultDir() : DEFAULTS.dir)
    const model = process.env.OPENCODE_PARAKEET_MODEL || DEFAULTS.model
    const server = join(dir, process.platform === "win32" ? "parakeet-server.exe" : "parakeet-server")
    const modelPath = isAbsolute(model) ? model : join(dir, model)

    const state = await probe(port)
    if (state === "up") {
      log("info", `server already running on port ${port}`)
      return
    }
    if (state === "unverified") {
      log("warn", `port ${port} is occupied but did not answer; not starting a duplicate server`)
      return
    }
    if (!existsSync(server)) {
      log("warn", `parakeet-server not found at ${server} - install it: https://github.com/moesuito/opencode-parakeet`)
      return
    }
    if (!existsSync(modelPath)) {
      log("warn", `model not found at ${modelPath} - install it: https://github.com/moesuito/opencode-parakeet`)
      return
    }

    log("info", `starting server on port ${port}`)
    const child = spawn(server, ["--model", modelPath, "--port", String(port)], {
      cwd: dir,
      detached: true,
      stdio: "ignore",
      windowsHide: true,
    })
    child.on("error", (error) => log("warn", `failed to start server: ${error.message}`))
    child.unref()

    void (async () => {
      for (let attempt = 0; attempt < 30; attempt++) {
        await new Promise((resolve) => setTimeout(resolve, 500))
        if ((await probe(port)) !== "down") {
          log("info", `server ready on port ${port}`)
          return
        }
      }
      log("warn", `server did not become ready on port ${port}`)
    })()
  },
}
