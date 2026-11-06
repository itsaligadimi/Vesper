import type { Metadata } from "next"
import { Fraunces, Outfit } from "next/font/google"

import "./globals.css"

const outfit = Outfit({
  subsets: ["latin"],
  variable: "--font-outfit",
})

const fraunces = Fraunces({
  subsets: ["latin"],
  variable: "--font-fraunces",
})

export const metadata: Metadata = {
  title: "Vesper — live wallpapers for Mac",
  description:
    "A native Mac app for live desktop wallpapers. The stills, thumbnails, and short loops live in a public repository instead of a private server.",
  openGraph: {
    title: "Vesper — live wallpapers for Mac",
    description:
      "Browse a public catalog of high-resolution stills and short loops, then set them on your Mac.",
    images: ["/media/cities/hong-kong/still.jpg"],
  },
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`dark ${outfit.variable} ${fraunces.variable}`}>
      <body className="min-h-screen bg-background font-sans text-foreground antialiased">{children}</body>
    </html>
  )
}
