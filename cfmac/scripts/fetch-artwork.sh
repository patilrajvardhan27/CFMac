#!/bin/bash
# Downloads cfmac's third-party artwork from its upstream sources and verifies every file
# against a pinned SHA-256. Licenses and credits: NOTICES.md.
#   Planet textures: Solar System Scope, CC BY 4.0
#   Runners:         RunCatNeo and RunnerGallery by Kyome22 (Takuto Nakamura) and contributors, Apache License 2.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Artwork"
SSS="https://www.solarsystemscope.com/textures/download"
RUNCAT="https://raw.githubusercontent.com/runcat-dev/RunCatNeo/592cd606e735ce20da98d9ae62ecf1a2608635d7/LocalPackage/Sources/UserInterface/Resources/Media.xcassets/Runners/Cat"
GALLERY="https://raw.githubusercontent.com/runcat-dev/RunnerGallery/b97965839f65a56ab483deed0e4291c7c068b382/runners"

# destination|url|sha256
FILES=(
  "earth.jpg|$SSS/2k_earth_daymap.jpg|767ee1dc6eb3802699bfccf6f264880f8acd0b80de3191cd24984fe279b07b7c"
  "earth-clouds.jpg|$SSS/2k_earth_clouds.jpg|fffd7f68d41b37274822150e54a6ef605af1d3ec35624d9f628c3b896bfa42ed"
  "moon.jpg|$SSS/2k_moon.jpg|2764ba6535ea0481a062846ee033cc7a909dae05b31a8fd13f3e98f3a7fd92bd"
  "mercury.jpg|$SSS/2k_mercury.jpg|5a5c80607f643496bac9a631e71957def35ed788895f18b678ac849c2b38e48a"
  "venus.jpg|$SSS/2k_venus_atmosphere.jpg|225012ad4911730605c4e189ca2a3bf674fce50cc48aab4102b936b47d6991ac"
  "mars.jpg|$SSS/2k_mars.jpg|2d187f3e77a98eaa8cea5f4cc722f633c122ef170b9e94ace6b5fb6cbc3f8e01"
  "jupiter.jpg|$SSS/2k_jupiter.jpg|b0f04d005350252636b0e3396fc592548cbd9e9126b269d32d5c6abd4b0e4f2b"
  "saturn.jpg|$SSS/2k_saturn.jpg|54a900ca9bf7ab62e70f862852759abdf342e6d6436a95a2fe9ebdb6bcd3bbac"
  "saturn-ring.png|$SSS/2k_saturn_ring_alpha.png|4b0644b2f3ef259fd0bfaedd9dc52f9e7d9738f65f50363e8c4dd19f650d7334"
  "uranus.jpg|$SSS/2k_uranus.jpg|d15239d46f82d3ea13d2b260b5b29b2a382f42f2916dae0694d0387b1204a09d"
  "neptune.jpg|$SSS/2k_neptune.jpg|cb42ea82709741d28b0af44d8b283cbc6dbd0c521a7f0e1e1e010ade00977df6"
  "sun.jpg|$SSS/2k_sun.jpg|ff0f076ba65e03b5ab518451bc96699325be38e3ccbdd5869ee1c00f3a0c8816"
  "runners/cat/frame-0.png|$RUNCAT/cat-frame-0.imageset/cat-frame-0.png|801e3571b11fd16b3efbc1f65b651df871c2830aadd76da53e600c727927f9b5"
  "runners/cat/frame-1.png|$RUNCAT/cat-frame-1.imageset/cat-frame-1.png|02eb14ae0f25f585bfe68834880a7cc9c9a9c1590d67a5f1bac2a5f26191a5a9"
  "runners/cat/frame-2.png|$RUNCAT/cat-frame-2.imageset/cat-frame-2.png|f7eb0ecfe1144d6232dfd9160b96fe452125ded56d3f6d59d7c6e371a537ceb9"
  "runners/cat/frame-3.png|$RUNCAT/cat-frame-3.imageset/cat-frame-3.png|55458fc0e83ba7f5f5764945beb8ad3c33dd702f2b2e76040a9d29ee7c7c115e"
  "runners/cat/frame-4.png|$RUNCAT/cat-frame-4.imageset/cat-frame-4.png|52da0d6f9d1ba8d2c0d5aee692f4d8278418f684bd35dafe95ad766265d6c0e1"
)

# runner|sha256 of <runner>-frames.zip
RUNNERS=(
  "beagle|6b2670fd38b0259408283a52463bce12c33618ad332afdfaee742a9c888d4fc3"
  "frog|191491da8b648bfcaa662f1b096f818f0ed436c58d318a4c6b73cc9e7f21c6f8"
  "dinosaur|92b81f54affd6d3a8306ddf62db0e44245fac9c83e8c544f4648ed48c21b2ee0"
  "rubber-duck|db22b1706582541abde0b87d42ecbd7ac9006918e757eb1bf738077f82bc125f"
  "rabbit|44977c56b47e10608e1fd756d576e6481971ed2f5c89b270b45461a77c431d23"
  "fox|b213cf287b147bf7aef70d4db29634efdd63748d275c5f54032ab09dde6b6a5c"
  "bird|cf0802b643bb5ed5498fc7a5b18bfb1b2fd23e185b119da8cc50ad2a15043ea3"
  "chicken|de2d29820734eb78e418d5a7118f5aa632c0d7e0ecbf791fb8e1eaf7426c7109"
  "deer|06406108e98ab188308be95b0779613981605bb489090b1198fb55e95ba48d3d"
  "dolphin|7c97bb618798fe298d54cd96f954c68111f34061505fcaf85db329c738e8c20b"
  "horse|626267cdb939223f8a7b3c129f447484395cd2c8bf47a868cf2f974e12268638"
  "otter|681f1f431fa95034fa6847832b2af5c62651a9a7a8abe8879c4866d464392da5"
  "squirrel|9ab854c1d5e8e02c695d752a5e1361cca56c78561b8df5ed3f8c1e1705cd2264"
  "turtle|6b704b6195068aeb64140b0d8d8a368e9773d53fbbae809cf8ccbb2bdf009611"
  "shiba-inu|82ea14c7a199f6039b4504a021403029ed1444e0c621c3bac17b2f9e2630688b"
  "welsh-corgi|b8b610e31ac35e527fa6499c52b4762cde198d699bc52c9f6563772636cdeff6"
)

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

fetch() { # url expected-sha output
  curl -fsSL --retry 3 -o "$3" "$1"
  local actual
  actual="$(sha "$3")"
  if [[ "$actual" != "$2" ]]; then
    echo "error: $(basename "$3") hash mismatch (expected $2, got $actual)" >&2
    exit 1
  fi
}

require_image() {
  case "$(file -b --mime-type "$1")" in
    image/jpeg|image/png) ;;
    *) echo "error: $1 is not an image" >&2; exit 1 ;;
  esac
}

for entry in "${FILES[@]}"; do
  IFS='|' read -r name url expected <<<"$entry"
  [[ -f "$DEST/$name" && "$(sha "$DEST/$name")" == "$expected" ]] && continue
  mkdir -p "$(dirname "$STAGE/$name")"
  fetch "$url" "$expected" "$STAGE/$name"
  require_image "$STAGE/$name"
done

for entry in "${RUNNERS[@]}"; do
  IFS='|' read -r runner expected <<<"$entry"
  marker="$DEST/runners/$runner/.source-sha256"
  [[ -f "$marker" && "$(cat "$marker")" == "$expected" ]] && continue
  zip="$STAGE/$runner.zip"
  fetch "$GALLERY/$runner/$runner-frames.zip" "$expected" "$zip"
  # Extract only PNG frames, flattened, into a fresh folder, and rename to frame-N.png.
  raw="$STAGE/$runner-raw"
  mkdir -p "$raw" "$STAGE/runners/$runner"
  unzip -q -j "$zip" '*.png' -d "$raw"
  for frame in "$raw"/*.png; do
    index="$(basename "$frame" .png | sed -E 's/.*-frame-([0-9]+)$/\1/')"
    [[ "$index" =~ ^[0-9]+$ ]] || { echo "error: unexpected file $(basename "$frame")" >&2; exit 1; }
    require_image "$frame"
    mv "$frame" "$STAGE/runners/$runner/frame-$index.png"
  done
  echo "$expected" > "$STAGE/runners/$runner/.source-sha256"
  rm -rf "$raw" "$zip"
done

mkdir -p "$DEST"
(cd "$STAGE" && find . -type f) | while read -r relative; do
  mkdir -p "$DEST/$(dirname "$relative")"
  mv -f "$STAGE/$relative" "$DEST/$relative"
done
rm -f "$DEST"/runner-*.png
echo "Artwork ready in $DEST"
