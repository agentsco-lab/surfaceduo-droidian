#!/bin/bash
# release-add-boot.sh: the port's boot image put into a release
# (out/release/<name>/) - for a phone coming from stock Android, which has
# no port kernel on its slot: item/grid RAM-boots this image, and writes it
# to the slots only once it booted Linux on that phone (SAFETY.md, rule 1).
#
#   tools/release-add-boot.sh out/release/<name> out/boot-<...>.img
#
# The image is validated first (tools/flash-safely.sh validate: header v2,
# arm64 kernel, its DTB, androidboot.hardware). Use the boot image the
# phones run - the one confirmed on a Duo (out/flash-state.json), not a
# trial build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REL="${1:?release directory}"
IMG="${2:?boot image}"
[ -f "$REL/manifest.json" ] || { echo "release-add-boot: $REL has no manifest.json" >&2; exit 1; }
"$ROOT/tools/flash-safely.sh" validate "$IMG"
install -m 644 "$IMG" "$REL/boot.img"
SHA=$(sha256sum "$REL/boot.img" | cut -d' ' -f1)
SIZE=$(stat -c %s "$REL/boot.img")
python3 - "$REL/manifest.json" "$SHA" "$SIZE" "$(basename "$IMG")" <<'PY'
import json, sys
path, sha, size, origin = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
m = json.load(open(path))
m["boot"] = {"file": "boot.img", "size": size, "sha256": sha, "from": origin}
open(path, "w").write(json.dumps(m, indent=2) + "\n")
PY
# The sums again (the manifest changed, the boot came).
if [ -f "$REL/SHA256SUMS" ]; then
    grep -v '  \(manifest.json\|boot.img\)$' "$REL/SHA256SUMS" > "$REL/SHA256SUMS.new" || true
    (cd "$REL" && sha256sum manifest.json boot.img) >> "$REL/SHA256SUMS.new"
    mv "$REL/SHA256SUMS.new" "$REL/SHA256SUMS"
fi
echo "release-add-boot: $REL/boot.img ($SHA)"
