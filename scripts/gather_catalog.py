#!/usr/bin/env python3
"""Build catalog/ from freely licensed photographs and short footage.

Stills are downloaded from Wikimedia Commons (a scaled JPEG, at most 3840px
wide). Each one is cropped to 16:9, saved as a high-resolution still, a small
thumbnail, and a seamless 10-second camera drift. A few entries use real
footage instead of a drift. Three abstract loops are original frames rendered
here and released as CC0.

Re-runnable. Needs ffmpeg and network access to Commons.
"""

from __future__ import annotations

import html
import json
import re
import subprocess
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "catalog"
UA = "VesperCatalog/1.0 (open-source macOS live wallpaper; catalog builder)"
FOOTAGE = Path("/tmp/vesper-footage")

CATEGORIES = [
    {"id": "nature", "name": "Nature", "blurb": "Forests, falls, and paths with room to breathe."},
    {"id": "ocean", "name": "Ocean", "blurb": "Shores, stacks, and water the color of glass."},
    {"id": "mountains", "name": "Mountains", "blurb": "Ridges, lakes, and weather caught on the peaks."},
    {"id": "cosmos", "name": "Cosmos", "blurb": "Aurora, nebulae, and the Earth from orbit."},
    {"id": "cities", "name": "Cities", "blurb": "Night skylines with the lights still on."},
    {"id": "aerial", "name": "Aerial", "blurb": "The long view: cloud decks, terraces, and river mist."},
    {"id": "weather", "name": "Weather", "blurb": "Storm light, snow, and a volcano that will not sit still."},
    {"id": "minimal", "name": "Minimal", "blurb": "Dunes, pattern, and quiet color."},
    {"id": "abstract", "name": "Abstract", "blurb": "Original light studies made for the desktop."},
]

# focus is (x, y) in 0..1, where the 16:9 crop is anchored.
ENTRIES: list[dict] = [
    dict(id="nature-beauchamp-falls", title="Beauchamp Falls", category="nature",
         file="File:Beech Forest (AU), Great Otway National Park, Beauchamp Falls -- 2019 -- 1271.jpg",
         location="Great Otway National Park, Australia",
         tags=["waterfall", "forest", "green", "calm", "mist"], focus=(0.62, 0.46), featured=True),
    dict(id="nature-laurel-fog", title="Laurel in the Fog", category="nature",
         file="File:Fanal (Madeira, Portugal), Lorbeerwald -- 2025 -- 1532.jpg",
         location="Fanal, Madeira",
         tags=["fog", "forest", "trees", "calm", "green", "mist"], focus=(0.52, 0.42)),
    dict(id="nature-autumn-path", title="Autumn Path", category="nature",
         file="File:Forest path through yellow autumn leaves in Tuntorp 1.jpg",
         location="Tuntorp, Sweden",
         tags=["autumn", "forest", "path", "warm", "gold", "cozy"], focus=(0.5, 0.48)),
    dict(id="ocean-crete-shore", title="Crete Shore", category="ocean",
         file="File:Northern coast Crete rocks waves detail.jpg",
         location="Northern Crete",
         tags=["ocean", "waves", "rocks", "blue", "calm", "coast"], focus=(0.55, 0.42)),
    dict(id="ocean-sea-stacks", title="Sea Stacks", category="ocean",
         file="File:Second Beach Olympic June 2018 008.jpg",
         location="Second Beach, Olympic National Park",
         tags=["ocean", "beach", "waves", "coast", "blue", "calm"], focus=(0.42, 0.4), featured=True),
    dict(id="ocean-padar-bays", title="Padar Bays", category="ocean",
         file="File:Padar Island, Komodo National Park, Indonesia, 20250822 0929 2659.jpg",
         location="Padar Island, Indonesia",
         tags=["ocean", "islands", "turquoise", "coast", "aerial", "blue"], focus=(0.55, 0.46)),
    dict(id="mountains-maligne-lake", title="Maligne Lake", category="mountains",
         file="File:Sunrise at Maligne lake 2.jpg",
         location="Maligne Lake, Canada",
         tags=["lake", "mountains", "forest", "calm", "reflection", "mist"], focus=(0.42, 0.4), featured=True),
    dict(id="mountains-alpenglow", title="Alpenglow Range", category="mountains",
         file="File:Verkhoyansk Range, Republic of Sakha (Yakutia), Russia - 2019.jpg",
         location="Verkhoyansk Range, Sakha",
         tags=["mountains", "snow", "alpenglow", "dramatic", "warm", "aerial"], focus=(0.5, 0.48), featured=True),
    dict(id="mountains-denali", title="Denali Above the Clouds", category="mountains",
         file="File:Denali - Above the Clouds.jpg",
         location="Denali, Alaska",
         tags=["mountain", "clouds", "snow", "blue", "calm", "peak"], focus=(0.5, 0.38)),
    dict(id="cosmos-milky-way", title="Milky Way Over the Lake", category="cosmos",
         file="File:Bontecou Lake Milky Way panorama.jpg",
         location="Bontecou Lake, New York",
         tags=["stars", "night", "milky way", "lake", "calm", "space"], focus=(0.58, 0.38)),
    dict(id="cosmos-rosette", title="Rosette Nebula", category="cosmos",
         file="File:Rosette Nebula Captured with DECam (noirlab2424a).jpg",
         location="Monoceros",
         tags=["nebula", "space", "stars", "color", "dramatic", "cosmos"], focus=(0.5, 0.5), featured=True),
    dict(id="cosmos-myvatn", title="Lights Over Mývatn", category="cosmos",
         file="File:039 Northern lights over Mývatn (Iceland) Photo by Giles Laurent.jpg",
         location="Mývatn, Iceland",
         tags=["aurora", "night", "stars", "lake", "green", "calm"], focus=(0.5, 0.34)),
    dict(id="cities-hong-kong", title="Harbour Night", category="cities",
         file="File:Hong Kong Harbour Night 2019-06-11.jpg",
         location="Hong Kong",
         tags=["city", "night", "skyline", "lights", "harbour"], focus=(0.48, 0.5), featured=True),
    dict(id="cities-singapore", title="Marina Lights", category="cities",
         file="File:Skylines of the Central Business District at night in Singapore.jpg",
         location="Singapore",
         tags=["city", "night", "skyline", "lights", "water"], focus=(0.5, 0.48)),
    dict(id="cities-shanghai", title="The Bund", category="cities",
         file="File:Shanghai skyline at night.jpg",
         location="Shanghai",
         tags=["city", "night", "skyline", "lights", "river"], focus=(0.5, 0.55)),
    dict(id="aerial-teide", title="Teide Above the Sea", category="aerial",
         file="File:20250708 Teide 03.jpg",
         location="Tenerife",
         tags=["volcano", "clouds", "aerial", "blue", "island", "calm"], focus=(0.5, 0.55)),
    dict(id="aerial-terraces", title="Longsheng Terraces", category="aerial",
         file="File:Longsheng Rice Terraces November 2017 014.jpg",
         location="Longsheng, China",
         tags=["terraces", "green", "aerial", "hills", "calm"], focus=(0.42, 0.52)),
    dict(id="aerial-river-mist", title="River Mist", category="aerial",
         file="File:Morning fog over Keravanjoki river in Vantaa, Finland, 2021 October.jpg",
         location="Vantaa, Finland",
         tags=["fog", "river", "autumn", "aerial", "mist", "calm", "gold"], focus=(0.42, 0.5)),
    dict(id="weather-litli", title="Litli-Hrútur", category="weather",
         file="File:001 Volcano eruption of Litli-Hrútur in Iceland in 2023 Photo by Giles Laurent.jpg",
         location="Litli-Hrútur, Iceland",
         tags=["volcano", "lava", "dramatic", "fire", "storm"], focus=(0.4, 0.5), featured=True),
    dict(id="weather-kirkjufell", title="Kirkjufell in the Rain", category="weather",
         file="File:Kirkjufell, Iceland, 20240714 1631 0713.jpg",
         location="Kirkjufell, Iceland",
         tags=["mountain", "rain", "storm", "waterfall", "dramatic", "green"], focus=(0.48, 0.42)),
    dict(id="weather-tatras", title="High Tatras", category="weather",
         file="File:Winter in Tatry Mountains - Poland.jpg",
         location="Tatra Mountains, Poland",
         tags=["snow", "mountains", "winter", "clouds", "cold", "white"], focus=(0.55, 0.48)),
    dict(id="minimal-thar", title="Thar Dune", category="minimal",
         file="File:Dunes, Désert du Thar.jpg",
         location="Thar Desert",
         tags=["dune", "sand", "minimal", "warm", "calm", "desert"], focus=(0.55, 0.48)),
    dict(id="minimal-namib", title="Namib Light", category="minimal",
         file="File:Namib-Naukluft Sand Dunes (2011).jpg",
         location="Namib-Naukluft, Namibia",
         tags=["dune", "sand", "minimal", "warm", "gold", "desert", "dramatic"], focus=(0.5, 0.45), featured=True),
    dict(id="minimal-coral", title="Coral Field", category="minimal",
         file="File:Coral (Astreopora myriophthalma), mar Rojo, Egipto, 2023-04-18, DD 15.jpg",
         location="Red Sea, Egypt",
         tags=["coral", "pattern", "minimal", "ocean", "gold", "texture"], focus=(0.5, 0.5)),
]

FOOTAGE_ENTRIES = [
    dict(id="cosmos-lake-aurora", title="Lake Aurora", category="cosmos",
         file="File:Aurora borealis timelapse.webm",
         location="Lapland",
         tags=["aurora", "night", "lake", "green", "stars", "motion"],
         footage="Aurora_borealis_timelapse.webm", start=62, duration=10,
         featured=True, hero=True),
    dict(id="cosmos-earth-limb", title="Earth at the Limb", category="cosmos",
         file="File:ISS 4K Crew Earth Observations.webm",
         location="Low Earth orbit",
         tags=["earth", "space", "clouds", "orbit", "blue", "nasa"],
         footage="ISS_4K_Crew_Earth_Observations.webm", start=20, duration=10,
         featured=True),
]


def api(params: dict) -> dict:
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=90) as response:
        return json.load(response)


def clean(value: str) -> str:
    text = re.sub(r"<[^>]+>", " ", value or "")
    text = html.unescape(text)
    text = text.replace("\xa0", " ")
    return re.sub(r"\s+", " ", text).strip()


def fetch_metadata(titles: list[str]) -> dict[str, dict]:
    found: dict[str, dict] = {}
    for index in range(0, len(titles), 8):
        chunk = titles[index : index + 8]
        data = api(
            {
                "action": "query",
                "format": "json",
                "prop": "imageinfo",
                "titles": "|".join(chunk),
                "iiprop": "url|size|mime|extmetadata",
                "iiurlwidth": "3840",
            }
        )
        for page in data["query"]["pages"].values():
            if "missing" in page or "imageinfo" not in page:
                print("MISSING", page.get("title"))
                continue
            info = page["imageinfo"][0]
            meta = info.get("extmetadata") or {}
            found[page["title"]] = {
                "width": info.get("width") or 0,
                "height": info.get("height") or 0,
                "download": info.get("thumburl") or info.get("url"),
                "page": "https://commons.wikimedia.org/wiki/" + urllib.parse.quote(page["title"].replace(" ", "_")),
                "license": (meta.get("LicenseShortName") or {}).get("value", "See source"),
                "license_url": (meta.get("LicenseUrl") or {}).get("value", ""),
                "artist": clean((meta.get("Artist") or {}).get("value", "")),
                "credit": clean((meta.get("Credit") or {}).get("value", "")),
                "description": clean((meta.get("ImageDescription") or {}).get("value", "")),
            }
        time.sleep(0.4)
    return found


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=180) as response, tmp.open("wb") as handle:
        while True:
            chunk = response.read(1024 * 256)
            if not chunk:
                break
            handle.write(chunk)
    tmp.replace(dest)


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def even(value: int) -> int:
    return max(2, value - (value % 2))


def probe_size(src: Path) -> tuple[int, int]:
    probe = subprocess.check_output(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", str(src),
        ],
        text=True,
    ).strip()
    width, height = (int(part) for part in probe.split("x"))
    return width, height


def target_size(src: Path) -> tuple[int, int]:
    width, height = probe_size(src)
    # Largest 16:9 frame that fits inside the source and inside 3840x2160.
    if width / height > 16 / 9:
        out_h = min(2160, height)
        out_w = int(out_h * 16 / 9)
    else:
        out_w = min(3840, width)
        out_h = int(out_w * 9 / 16)
    return even(out_w), even(out_h)


def make_still(src: Path, dest: Path, focus: tuple[float, float]) -> tuple[int, int]:
    out_w, out_h = target_size(src)
    fx, fy = focus
    vf = (
        f"scale={out_w}:{out_h}:force_original_aspect_ratio=increase,"
        f"crop={out_w}:{out_h}:(in_w-{out_w})*{fx}:(in_h-{out_h})*{fy}"
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    run(["ffmpeg", "-y", "-i", str(src), "-vf", vf, "-q:v", "3", str(dest)])
    return out_w, out_h


def make_thumb(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    run(["ffmpeg", "-y", "-i", str(src), "-vf", "scale=640:-2", "-q:v", "5", str(dest)])


def make_drift(src: Path, dest: Path) -> float:
    """Seamless 10s pan. The sine term is zero at both ends, so the loop matches."""
    vf = (
        "scale=2200:1238:force_original_aspect_ratio=increase,"
        "crop=1920:1080:(in_w-1920)*0.5*(1+0.9*sin(2*PI*t/10)):(in_h-1080)*0.5*(1+0.4*sin(2*PI*t/10+0.7)),"
        "fps=24,format=yuv420p"
    )
    dest.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "ffmpeg", "-y", "-loop", "1", "-framerate", "24", "-i", str(src),
            "-vf", vf, "-t", "10", "-an",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(dest),
        ]
    )
    return 10.0


def make_footage(src: Path, dest_video: Path, dest_still: Path, start: float, duration: float) -> tuple[int, int, float]:
    dest_video.parent.mkdir(parents=True, exist_ok=True)
    vf = "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=24,format=yuv420p"
    run(
        [
            "ffmpeg", "-y", "-ss", str(start), "-t", str(duration), "-i", str(src),
            "-vf", vf, "-an",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "19",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(dest_video),
        ]
    )
    run(
        [
            "ffmpeg", "-y", "-ss", str(start + 1.5), "-i", str(src), "-frames:v", "1",
            "-vf", "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080",
            "-q:v", "3", str(dest_still),
        ]
    )
    return 1920, 1080, duration


def render_abstracts() -> list[dict]:
    import numpy as np

    specs = [
        ("abstract-afterglow", "Afterglow", ["abstract", "warm", "gold", "calm", "dusk", "minimal"]),
        ("abstract-veil", "Veil", ["abstract", "aurora", "green", "night", "calm", "motion"]),
        ("abstract-slow-dune", "Slow Dune", ["abstract", "sand", "minimal", "warm", "calm", "dune"]),
    ]
    width, height, frames, fps = 1920, 1080, 240, 24
    ys = np.linspace(0, 1, height, dtype=np.float32)[:, None]
    xs = np.linspace(0, 1, width, dtype=np.float32)[None, :]
    rng = np.random.default_rng(7)
    grain = rng.normal(0, 1.6, size=(height, width, 1)).astype(np.float32)

    def encode(name: str, painter) -> None:
        folder = CATALOG / "abstract" / name.removeprefix("abstract-")
        folder.mkdir(parents=True, exist_ok=True)
        video = folder / "loop.mp4"
        cmd = [
            "ffmpeg", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
            "-s", f"{width}x{height}", "-r", str(fps), "-i", "-",
            "-an", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(video),
        ]
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        assert proc.stdin is not None
        still = None
        for index in range(frames):
            t = index / fps
            frame = painter(t)
            if index == frames // 2:
                still = frame
            proc.stdin.write(frame.tobytes())
        proc.stdin.close()
        if proc.wait() != 0:
            raise RuntimeError(f"ffmpeg failed for {name}")
        still_path = folder / "still.jpg"
        # write the mid frame through ffmpeg so the jpeg matches the video
        raw = folder / "still.rgb"
        raw.write_bytes(still.tobytes())
        run(
            [
                "ffmpeg", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                "-s", f"{width}x{height}", "-i", str(raw), "-q:v", "3", str(still_path),
            ]
        )
        raw.unlink()
        make_thumb(still_path, folder / "thumb.jpg")

    def afterglow(t: float):
        sx = 0.62 + 0.06 * np.sin(2 * np.pi * t / 10)
        sy = 0.58 + 0.015 * np.sin(2 * np.pi * t / 10)
        dist = np.sqrt((xs - sx) ** 2 + ((ys - sy) * 0.72) ** 2)
        glow = np.exp(-((dist * 3.4) ** 2)).astype(np.float32)[..., None]
        horizon = np.clip((ys - 0.46) * 2.2, 0, 1).astype(np.float32)[..., None]
        y = ys.astype(np.float32)[..., None]
        top = np.array([10, 12, 24], dtype=np.float32)
        mid = np.array([48, 32, 52], dtype=np.float32)
        bot = np.array([214, 146, 78], dtype=np.float32)
        sky = top * (1 - y) + mid * y
        sky = sky * (1 - horizon) + bot * horizon * 0.55
        col = sky * (1 - glow * 0.92) + np.array([255, 214, 170], dtype=np.float32) * glow
        col = col + grain * (0.35 + 0.25 * (1 - glow))
        return np.clip(col, 0, 255).astype(np.uint8)

    def veil(t: float):
        phase = 2 * np.pi * t / 10
        bands = np.sin((ys * 9.5) + phase + xs * 2.4) * 0.5 + 0.5
        bands += 0.35 * np.sin((ys * 17) - phase * 1.3 + xs * 5)
        bands = np.clip(bands, 0, 1).astype(np.float32)[..., None]
        mask = np.exp(-((ys - (0.38 + 0.04 * np.sin(phase))) ** 2) / 0.045).astype(np.float32)[..., None]
        night = np.array([6, 10, 22], dtype=np.float32)
        green = np.array([86, 214, 156], dtype=np.float32)
        violet = np.array([92, 78, 168], dtype=np.float32)
        tint = green * (1 - xs[..., None] * 0.35) + violet * (xs[..., None] * 0.45)
        col = night + tint * (bands * mask) * 0.85
        stars = ((np.sin(xs * 400) * np.sin(ys * 260)) > 0.995).astype(np.float32)[..., None]
        col = col + stars * np.array([220, 230, 255], dtype=np.float32) * 0.8
        col = col + grain * 0.25
        return np.clip(col, 0, 255).astype(np.uint8)

    def dune(t: float):
        phase = 2 * np.pi * t / 10
        ridges = np.sin((xs * 18 + ys * 2.2) + phase)
        light = np.clip(0.55 + 0.45 * ridges, 0, 1).astype(np.float32)[..., None]
        shadow = np.clip(0.5 + 0.5 * np.sin((xs * 18 + ys * 2.2) + phase + 0.6), 0, 1).astype(np.float32)[..., None]
        sand = np.array([214, 164, 96], dtype=np.float32)
        shade = np.array([92, 58, 32], dtype=np.float32)
        sky_color = np.array([232, 214, 190], dtype=np.float32)
        ground = shade * (1 - light) + sand * light
        sky_mask = np.clip((0.28 - ys) / 0.28, 0, 1).astype(np.float32)[..., None]
        col = ground * (1 - sky_mask) + sky_color * sky_mask
        col = col * (0.92 + 0.08 * shadow)
        col = col + grain * 0.3
        return np.clip(col, 0, 255).astype(np.uint8)

    painters = {"abstract-afterglow": afterglow, "abstract-veil": veil, "abstract-slow-dune": dune}
    records = []
    for wallpaper_id, title, tags in specs:
        print(f"abstract {title}")
        encode(wallpaper_id, painters[wallpaper_id])
        slug = wallpaper_id.removeprefix("abstract-")
        records.append(
            {
                "id": wallpaper_id,
                "title": title,
                "category": "abstract",
                "location": "Original",
                "author": "Vesper",
                "license": "CC0 1.0",
                "licenseUrl": "https://creativecommons.org/publicdomain/zero/1.0/",
                "sourceUrl": "",
                "motion": "original",
                "width": width,
                "height": height,
                "videoWidth": width,
                "videoHeight": height,
                "duration": 10,
                "tags": tags,
                "featured": wallpaper_id == "abstract-afterglow",
                "hero": False,
                "thumbnail": f"abstract/{slug}/thumb.jpg",
                "image": f"abstract/{slug}/still.jpg",
                "video": f"abstract/{slug}/loop.mp4",
            }
        )
    return records


def rel(entry_id: str, category: str, name: str) -> str:
    slug = entry_id.split("-", 1)[1]
    return f"{category}/{slug}/{name}"


def build() -> None:
    titles = [entry["file"] for entry in ENTRIES + FOOTAGE_ENTRIES]
    print(f"resolving {len(titles)} commons files")
    meta = fetch_metadata(titles)
    wallpapers: list[dict] = []

    for entry in ENTRIES:
        info = meta.get(entry["file"])
        if not info:
            raise SystemExit(f"no metadata for {entry['file']}")
        if any(flag in info["license"] for flag in ("NC", "ND")):
            raise SystemExit(f"license not reusable: {entry['file']} {info['license']}")
        slug = entry["id"].split("-", 1)[1]
        folder = CATALOG / entry["category"] / slug
        still = folder / "still.jpg"
        video = folder / "loop.mp4"
        thumb = folder / "thumb.jpg"
        if still.exists() and video.exists() and thumb.exists() and video.stat().st_size > 20000:
            width, height = probe_size(still)
            print(f"keep {entry['title']} {width}x{height}")
            wallpapers.append(record(entry, info, width, height, 1920, 1080, 10.0, "drift"))
            continue
        source = folder / "source.jpg"
        print(f"still {entry['title']} ({info['license']})")
        if not source.exists() or source.stat().st_size < 1000:
            download(info["download"], source)
            time.sleep(0.3)
        width, height = make_still(source, still, entry["focus"])
        make_thumb(still, thumb)
        print(f"  drift {width}x{height}")
        duration = make_drift(still, video)
        source.unlink(missing_ok=True)
        wallpapers.append(record(entry, info, width, height, 1920, 1080, duration, "drift"))

    for entry in FOOTAGE_ENTRIES:
        info = meta.get(entry["file"])
        if not info:
            raise SystemExit(f"no metadata for {entry['file']}")
        slug = entry["id"].split("-", 1)[1]
        folder = CATALOG / entry["category"] / slug
        if (folder / "loop.mp4").exists() and (folder / "still.jpg").exists() and (folder / "thumb.jpg").exists():
            width, height = probe_size(folder / "still.jpg")
            print(f"keep footage {entry['title']}")
            wallpapers.append(record(entry, info, width, height, width, height, float(entry["duration"]), "footage"))
            continue
        src = FOOTAGE / entry["footage"]
        if not src.exists():
            raise SystemExit(f"missing footage {src}")
        print(f"footage {entry['title']}")
        width, height, duration = make_footage(
            src, folder / "loop.mp4", folder / "still.jpg", entry["start"], entry["duration"]
        )
        make_thumb(folder / "still.jpg", folder / "thumb.jpg")
        wallpapers.append(record(entry, info, width, height, width, height, duration, "footage"))

    wallpapers.extend(render_abstracts())

    # Stable order: category order, then title.
    order = {category["id"]: index for index, category in enumerate(CATEGORIES)}
    wallpapers.sort(key=lambda item: (order[item["category"]], item["title"]))
    manifest = {
        "version": 1,
        "name": "Vesper",
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "about": "Live wallpapers for Mac. Files live in this repository. Thumbnails are small on purpose so the library can open before any video is fetched.",
        "categories": CATEGORIES,
        "wallpapers": wallpapers,
    }
    (CATALOG / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    source_path = CATALOG / "source.json"
    previous: dict = {}
    if source_path.exists():
        try:
            previous = json.loads(source_path.read_text())
        except json.JSONDecodeError:
            previous = {}
    source_path.write_text(
        json.dumps(
            {
                "repository": previous.get("repository") or "",
                "branch": previous.get("branch") or "main",
                "note": "After this project is published on GitHub, set repository to owner/name. The Mac app then refreshes this catalog from raw.githubusercontent.com.",
            },
            indent=2,
        )
        + "\n"
    )
    print(f"wrote {len(wallpapers)} wallpapers")


def record(entry, info, width, height, video_w, video_h, duration, motion) -> dict:
    slug = entry["id"].split("-", 1)[1]
    category = entry["category"]
    return {
        "id": entry["id"],
        "title": entry["title"],
        "category": category,
        "location": entry["location"],
        "author": info["artist"] or "Unknown",
        "license": info["license"],
        "licenseUrl": info["license_url"],
        "sourceUrl": info["page"],
        "motion": motion,
        "width": width,
        "height": height,
        "videoWidth": video_w,
        "videoHeight": video_h,
        "duration": duration,
        "tags": entry["tags"],
        "featured": bool(entry.get("featured")),
        "hero": bool(entry.get("hero")),
        "thumbnail": f"{category}/{slug}/thumb.jpg",
        "image": f"{category}/{slug}/still.jpg",
        "video": f"{category}/{slug}/loop.mp4",
    }


if __name__ == "__main__":
    build()
