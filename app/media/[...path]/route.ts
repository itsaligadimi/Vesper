import { createReadStream } from "node:fs"
import { stat } from "node:fs/promises"
import path from "node:path"
import { Readable } from "node:stream"

const ROOT = path.resolve(process.cwd(), "catalog")

const TYPES: Record<string, string> = {
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
  ".mp4": "video/mp4",
  ".json": "application/json",
  ".webm": "video/webm",
}

export async function GET(request: Request, context: { params: Promise<{ path: string[] }> }) {
  const { path: parts } = await context.params
  if (!parts?.length || parts.some((part) => part === ".." || part.includes("\0"))) {
    return new Response("Not found", { status: 404 })
  }
  const file = path.resolve(ROOT, ...parts)
  if (file !== ROOT && !file.startsWith(ROOT + path.sep)) {
    return new Response("Not found", { status: 404 })
  }
  let info
  try {
    info = await stat(file)
  } catch {
    return new Response("Not found", { status: 404 })
  }
  if (!info.isFile()) return new Response("Not found", { status: 404 })

  const type = TYPES[path.extname(file).toLowerCase()] ?? "application/octet-stream"
  const headers = new Headers({
    "Content-Type": type,
    "Accept-Ranges": "bytes",
    "Cache-Control": "public, max-age=86400",
  })
  const range = request.headers.get("range")
  if (range) {
    const match = /bytes=(\d+)-(\d*)/.exec(range)
    if (!match) return new Response("Bad range", { status: 416 })
    const start = Number(match[1])
    const end = Math.min(match[2] ? Number(match[2]) : info.size - 1, info.size - 1)
    if (start >= info.size || end < start) {
      headers.set("Content-Range", `bytes */${info.size}`)
      return new Response(null, { status: 416, headers })
    }
    headers.set("Content-Range", `bytes ${start}-${end}/${info.size}`)
    headers.set("Content-Length", String(end - start + 1))
    const stream = Readable.toWeb(createReadStream(file, { start, end })) as ReadableStream
    return new Response(stream, { status: 206, headers })
  }
  headers.set("Content-Length", String(info.size))
  const stream = Readable.toWeb(createReadStream(file)) as ReadableStream
  return new Response(stream, { status: 200, headers })
}
