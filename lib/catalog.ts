export type Wallpaper = {
  id: string
  title: string
  category: string
  location: string
  author: string
  license: string
  licenseUrl: string
  sourceUrl: string
  motion: string
  width: number
  height: number
  videoWidth: number
  videoHeight: number
  duration: number
  tags: string[]
  featured: boolean
  hero: boolean
  thumbnail: string
  image: string
  video: string
}

export type Category = {
  id: string
  name: string
  blurb: string
}

export type Catalog = {
  version: number
  name: string
  generatedAt: string
  about?: string
  categories: Category[]
  wallpapers: Wallpaper[]
}

const synonyms: Record<string, string[]> = {
  calm: ["calm", "mist", "fog", "lake", "minimal", "quiet", "still"],
  cozy: ["cozy", "autumn", "warm", "gold", "path"],
  night: ["night", "stars", "aurora", "city", "lights", "milky"],
  dramatic: ["dramatic", "storm", "volcano", "alpenglow", "lava", "rain"],
  space: ["space", "nebula", "orbit", "stars", "cosmos", "earth", "aurora"],
  ocean: ["ocean", "waves", "coast", "beach", "water", "shore"],
  cold: ["snow", "winter", "cold", "white"],
  warm: ["warm", "gold", "sand", "dune", "autumn", "alpenglow"],
  green: ["green", "forest", "trees", "terraces"],
  city: ["city", "skyline", "night", "lights", "harbour"],
}

export function mediaURL(relative: string) {
  return `/media/${relative.split("/").map(encodeURIComponent).join("/")}`
}

export function motionLabel(motion: string) {
  if (motion === "footage") return "Footage"
  if (motion === "original") return "Original"
  return "Camera drift"
}

export function matches(wallpaper: Wallpaper, query: string) {
  const terms = query
    .toLowerCase()
    .split(/\s+/)
    .map((term) => term.trim())
    .filter(Boolean)
  if (terms.length === 0) return true
  const haystack = [wallpaper.title, wallpaper.location, wallpaper.author, wallpaper.category, wallpaper.motion, ...wallpaper.tags]
    .join(" ")
    .toLowerCase()
  return terms.every((term) => {
    if (haystack.includes(term)) return true
    return (synonyms[term] ?? []).some((word) => haystack.includes(word))
  })
}
