import { readFileSync } from "node:fs"
import path from "node:path"

import type { Catalog } from "@/lib/catalog"

export function readCatalog(): Catalog {
  const file = path.join(process.cwd(), "catalog", "manifest.json")
  return JSON.parse(readFileSync(file, "utf8")) as Catalog
}
