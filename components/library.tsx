"use client"

import { useEffect, useMemo, useState } from "react"
import Image from "next/image"
import {
  Binoculars,
  Building2,
  Castle,
  Circle,
  CloudSun,
  Film,
  Heart,
  Leaf,
  Mountain,
  Paintbrush,
  Search,
  Sparkles,
  Swords,
  Waves,
  X,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import {
  matches,
  mediaURL,
  motionLabel,
  type Catalog,
  type Wallpaper,
} from "@/lib/catalog"

const ICONS: Record<string, typeof Leaf> = {
  nature: Leaf,
  ocean: Waves,
  mountains: Mountain,
  cosmos: Sparkles,
  cities: Building2,
  aerial: Binoculars,
  weather: CloudSun,
  minimal: Circle,
  abstract: Paintbrush,
  anime: Swords,
  fantasy: Castle,
}

type Section = "home" | "explore" | "favorites" | string

export function Library({ catalog }: { catalog: Catalog }) {
  const [section, setSection] = useState<Section>("home")
  const [query, setQuery] = useState("")
  const [selected, setSelected] = useState<Wallpaper | null>(null)
  const [favorites, setFavorites] = useState<string[]>([])

  useEffect(() => {
    const stored = window.localStorage.getItem("vesper.favorites")
    if (stored) setFavorites(JSON.parse(stored) as string[])
  }, [])

  function toggleFavorite(id: string) {
    setFavorites((current) => {
      const next = current.includes(id) ? current.filter((item) => item !== id) : [...current, id]
      window.localStorage.setItem("vesper.favorites", JSON.stringify(next))
      return next
    })
  }

  const hero = catalog.wallpapers.find((item) => item.hero) ?? catalog.wallpapers[0]
  const visible = useMemo(() => {
    return catalog.wallpapers.filter((wallpaper) => {
      if (section === "favorites" && !favorites.includes(wallpaper.id)) return false
      if (section !== "home" && section !== "explore" && section !== "favorites" && wallpaper.category !== section) {
        return false
      }
      return matches(wallpaper, query)
    })
  }, [catalog.wallpapers, favorites, query, section])

  const activeCategory = catalog.categories.find((category) => category.id === section)

  return (
    <div className="flex min-h-screen bg-background text-foreground">
      <aside className="sticky top-0 hidden h-screen w-60 shrink-0 flex-col border-r border-border bg-sidebar md:flex">
        <div className="px-5 pt-6 pb-4">
          <p className="font-serif text-2xl tracking-tight">Vesper</p>
          <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
            Live wallpapers for Mac. The collection is this repository.
          </p>
        </div>
        <ScrollArea className="min-h-0 flex-1 px-3">
          <nav className="flex flex-col gap-1">
            <NavButton current={section} id="home" label="Home" onSelect={setSection} icon={Sparkles} />
            <NavButton current={section} id="explore" label="Explore" onSelect={setSection} icon={Search} />
            <NavButton current={section} id="favorites" label="Favorites" onSelect={setSection} icon={Heart} />
            <Separator className="my-3" />
            <p className="px-2 pb-1 text-[11px] font-medium tracking-wide text-muted-foreground uppercase">Categories</p>
            {catalog.categories.map((category) => (
              <NavButton
                key={category.id}
                current={section}
                id={category.id}
                label={category.name}
                onSelect={setSection}
                icon={ICONS[category.id] ?? Film}
              />
            ))}
          </nav>
        </ScrollArea>
        <div className="border-t border-border p-4 text-xs leading-relaxed text-muted-foreground">
          Thumbnails load first. A loop is fetched only when you open it.
        </div>
      </aside>

      <main className="min-w-0 flex-1">
        <div className="sticky top-0 z-20 border-b border-border bg-background/85 px-4 py-3 backdrop-blur md:hidden">
          <div className="flex items-center justify-between gap-3">
            <p className="font-serif text-xl">Vesper</p>
            <SearchBox query={query} onChange={setQuery} />
          </div>
          <div className="mt-3 flex gap-2 overflow-x-auto pb-1">
            {[["home", "Home"], ["explore", "Explore"], ["favorites", "Favorites"], ...catalog.categories.map((category) => [category.id, category.name])].map(
              ([id, label]) => (
                <Button
                  key={id}
                  size="sm"
                  variant={section === id ? "default" : "outline"}
                  onClick={() => setSection(id)}
                >
                  {label}
                </Button>
              ),
            )}
          </div>
        </div>

        <div className="mx-auto flex max-w-6xl flex-col gap-8 px-4 py-6 md:px-8 md:py-8">
          <header className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
            <div>
              <h1 className="font-serif text-3xl tracking-tight md:text-4xl">
                {section === "home" && "Evening, on your desktop"}
                {section === "explore" && "Explore"}
                {section === "favorites" && "Favorites"}
                {activeCategory && activeCategory.name}
              </h1>
              <p className="mt-2 max-w-xl text-sm text-muted-foreground md:text-base">
                {section === "home" && "A public catalog of stills and short loops. No account, no wallpaper server."}
                {section === "explore" && "Search by place, color, or a mood like calm, night, or dramatic."}
                {section === "favorites" && "Hearts stay in this browser. The Mac app keeps its own list."}
                {activeCategory && activeCategory.blurb}
              </p>
            </div>
            <div className="hidden w-72 md:block">
              <SearchBox query={query} onChange={setQuery} />
            </div>
          </header>

          {section === "home" && hero && (
            <button
              type="button"
              onClick={() => setSelected(hero)}
              className="group relative h-[46vw] max-h-[460px] min-h-56 overflow-hidden rounded-3xl text-left ring-1 ring-white/10"
            >
              <video
                className="absolute inset-0 h-full w-full object-cover"
                src={mediaURL(hero.video)}
                poster={mediaURL(hero.image)}
                autoPlay
                muted
                loop
                playsInline
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black/75 via-black/10 to-transparent" />
              <div className="absolute right-4 bottom-4 left-4 md:right-8 md:bottom-8 md:left-8">
                <Badge className="bg-primary text-primary-foreground">Featured loop</Badge>
                <p className="mt-3 font-serif text-4xl text-white md:text-5xl">{hero.title}</p>
                <p className="mt-1 text-sm text-white/80">
                  {hero.location} · {hero.width}×{hero.height}
                </p>
              </div>
            </button>
          )}

          {section === "home" ? (
            catalog.categories.map((category) => {
              const items = visible.filter((wallpaper) => wallpaper.category === category.id)
              if (items.length === 0) return null
              return (
                <section key={category.id}>
                  <div className="mb-3 flex items-baseline justify-between gap-4">
                    <h2 className="font-serif text-2xl">{category.name}</h2>
                    <p className="hidden text-sm text-muted-foreground sm:block">{category.blurb}</p>
                  </div>
                  <div className="flex gap-4 overflow-x-auto pb-2">
                    {items.map((wallpaper) => (
                      <div key={wallpaper.id} className="w-64 shrink-0">
                        <WallpaperCard
                          wallpaper={wallpaper}
                          favorite={favorites.includes(wallpaper.id)}
                          onOpen={() => setSelected(wallpaper)}
                          onHeart={() => toggleFavorite(wallpaper.id)}
                        />
                      </div>
                    ))}
                  </div>
                </section>
              )
            })
          ) : visible.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-border px-6 py-16 text-center">
              <p className="font-serif text-2xl">Nothing in this view</p>
              <p className="mt-2 text-sm text-muted-foreground">
                {section === "favorites"
                  ? "Open a wallpaper and heart it. It will stay on this browser."
                  : "Try a broader word, or clear the search."}
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
              {visible.map((wallpaper) => (
                <WallpaperCard
                  key={wallpaper.id}
                  wallpaper={wallpaper}
                  favorite={favorites.includes(wallpaper.id)}
                  onOpen={() => setSelected(wallpaper)}
                  onHeart={() => toggleFavorite(wallpaper.id)}
                />
              ))}
            </div>
          )}

          <section id="install" className="rounded-3xl border border-border bg-card p-6 md:p-8">
            <h2 className="font-serif text-2xl">Put it on a Mac</h2>
            <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted-foreground">
              This page is the library. The Mac app is the same catalog with Apply: it sets the still as your desktop picture and plays the loop behind the icons. It reads the files from GitHub, so adding a wallpaper is a folder and a manifest entry, not a server deploy.
            </p>
            <pre className="mt-4 overflow-x-auto rounded-xl bg-black/40 p-4 text-xs leading-relaxed text-foreground">
              git clone &lt;this repository&gt;{"\n"}
              cd macos && ./scripts/build-app.sh
            </pre>
          </section>
        </div>
      </main>

      <Dialog open={selected !== null} onOpenChange={(open) => { if (!open) setSelected(null) }}>
        {selected && (
          <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-3xl" showCloseButton>
            <div className="overflow-hidden rounded-xl">
              <video
                key={selected.id}
                className="aspect-video w-full bg-black object-cover"
                src={mediaURL(selected.video)}
                poster={mediaURL(selected.thumbnail)}
                autoPlay
                muted
                loop
                playsInline
                controls
              />
            </div>
            <div className="flex items-start justify-between gap-4">
              <div>
                <DialogTitle className="font-serif text-2xl">{selected.title}</DialogTitle>
                <DialogDescription className="mt-1">
                  {selected.location} · {motionLabel(selected.motion)} · {Math.round(selected.duration)}s
                </DialogDescription>
              </div>
              <Button variant="outline" size="icon" onClick={() => toggleFavorite(selected.id)} aria-label="Favorite">
                <Heart className={favorites.includes(selected.id) ? "fill-primary text-primary" : ""} />
              </Button>
            </div>
            <p className="text-sm text-muted-foreground">
              {selected.width}×{selected.height} still · {selected.videoWidth}×{selected.videoHeight} loop. The grid used the thumbnail, so opening the library does not download every video.
            </p>
            <p className="text-sm">
              {selected.author}
              {selected.license ? ` · ${selected.license}` : ""}
            </p>
            <div className="flex flex-wrap gap-2">
              {selected.licenseUrl && (
                <Button variant="outline" nativeButton={false} render={<a href={selected.licenseUrl} target="_blank" rel="noreferrer" />}>
                  License
                </Button>
              )}
              {selected.sourceUrl && (
                <Button variant="outline" nativeButton={false} render={<a href={selected.sourceUrl} target="_blank" rel="noreferrer" />}>
                  Source
                </Button>
              )}
              <Button variant="outline" nativeButton={false} render={<a href={mediaURL(selected.image)} download />}>
                Still
              </Button>
              <Button nativeButton={false} render={<a href={mediaURL(selected.video)} download />}>Loop</Button>
            </div>
          </DialogContent>
        )}
      </Dialog>
    </div>
  )
}

function SearchBox({ query, onChange }: { query: string; onChange: (value: string) => void }) {
  return (
    <div className="relative">
      <Search className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
      <Input
        value={query}
        onChange={(event) => onChange(event.target.value)}
        placeholder="Try calm, night, dunes"
        className="h-9 pr-8 pl-8"
        aria-label="Search wallpapers"
      />
      {query && (
        <button
          type="button"
          className="absolute top-1/2 right-2 -translate-y-1/2 text-muted-foreground"
          onClick={() => onChange("")}
          aria-label="Clear search"
        >
          <X className="size-4" />
        </button>
      )}
    </div>
  )
}

function NavButton({
  current,
  id,
  label,
  onSelect,
  icon: Icon,
}: {
  current: string
  id: string
  label: string
  onSelect: (id: string) => void
  icon: typeof Leaf
}) {
  return (
    <Button
      variant={current === id ? "secondary" : "ghost"}
      className="w-full justify-start"
      onClick={() => onSelect(id)}
    >
      <Icon />
      {label}
    </Button>
  )
}

function WallpaperCard({
  wallpaper,
  favorite,
  onOpen,
  onHeart,
}: {
  wallpaper: Wallpaper
  favorite: boolean
  onOpen: () => void
  onHeart: () => void
}) {
  return (
    <article className="group">
      <button type="button" onClick={onOpen} className="block w-full text-left">
        <div className="relative aspect-video overflow-hidden rounded-2xl bg-muted ring-1 ring-white/8">
          {/* Thumbnails only. The loop stays unloaded until the wallpaper is opened. */}
          <Image
            src={mediaURL(wallpaper.thumbnail)}
            alt=""
            fill
            unoptimized
            sizes="(min-width: 1280px) 320px, 80vw"
            className="object-cover transition duration-500 group-hover:scale-[1.03]"
          />
          <div className="absolute inset-x-0 bottom-0 flex items-end justify-between bg-gradient-to-t from-black/70 to-transparent p-3">
            <Badge variant="secondary" className="bg-black/50 text-white">
              {motionLabel(wallpaper.motion)}
            </Badge>
          </div>
        </div>
        <p className="mt-2 text-sm font-medium">{wallpaper.title}</p>
        <p className="text-xs text-muted-foreground">{wallpaper.location}</p>
      </button>
      <button
        type="button"
        onClick={onHeart}
        className="mt-1 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
        aria-label={favorite ? `Remove ${wallpaper.title} from favorites` : `Favorite ${wallpaper.title}`}
      >
        <Heart className={favorite ? "size-3.5 fill-primary text-primary" : "size-3.5"} />
        {favorite ? "Saved" : "Save"}
      </button>
    </article>
  )
}
