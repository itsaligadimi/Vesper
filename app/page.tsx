import { Library } from "@/components/library"
import { readCatalog } from "@/lib/catalog.server"

export const dynamic = "force-dynamic"

export default function HomePage() {
  const catalog = readCatalog()
  return <Library catalog={catalog} />
}
