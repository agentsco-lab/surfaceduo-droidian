#!/bin/bash
# release-add-boot.sh: the port's boot image put into a release
# (out/release/<name>/) - for a phone coming from stock Android, which has
# no port kernel on its slot: item/grid RAM-boots this image, and writes it
# to the slots only once it booted Linux on that phone (SAFETY.md, rule 1).
#
#   tools/release-add-boot.sh out/release/<name> out/boot-<...>.img [vbmeta.img]
#
# With it the vbmeta the port runs with (verification off: tools'
# vbmeta-disabled.img, out/backups/.../vbmeta-disabled.img): written with
# the boot, as the port's install did.
#
# The image is validated first (tools/flash-safely.sh validate: header v2,
# arm64 kernel, its DTB, androidboot.hardware). Use the boot image the
# phones run - the one confirmed on a Duo (out/flash-state.json), not a
# trial build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REL="${1:?release directory}"
IMG="${2:?boot image}"
VBMETA="${3:-}"
[ -f "$REL/manifest.json" ] || { echo "release-add-boot: $REL has no manifest.json" >&2; exit 1; }
"$ROOT/tools/flash-safely.sh" validate "$IMG"
install -m 644 "$IMG" "$REL/boot.img"
SHA=$(sha256sum "$REL/boot.img" | cut -d' ' -f1)
SIZE=$(stat -c %s "$REL/boot.img")
if [ -n "$VBMETA" ]; then
    # Verification off (AVB flags bit 1), or it is not the port's.
    python3 -c 'import sys; b=open(sys.argv[1],"rb").read(124); sys.exit(0 if b[:4]==b"AVB0" and int.from_bytes(b[120:124],"big") & 2 else 1)' "$VBMETA" \
        || { echo "release-add-boot: $VBMETA is not a vbmeta with verification off" >&2; exit 1; }
    install -m 644 "$VBMETA" "$REL/vbmeta.img"
fi
python3 - "$REL/manifest.json" "$SHA" "$SIZE" "$(basename "$IMG")" "$REL/vbmeta.img" <<'PY'
import hashlib, json, os, sys
path, sha, size, origin, vb = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
m = json.load(open(path))
m["boot"] = {"file": "boot.img", "size": size, "sha256": sha, "from": origin}
if os.path.exists(vb):
    data = open(vb, "rb").read()
    m["vbmeta"] = {"file": "vbmeta.img", "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
open(path, "w").write(json.dumps(m, indent=2) + "\n")
PY
# The sums again (the manifest changed, the boot came).
if [ -f "$REL/SHA256SUMS" ]; then
    grep -v '  \(manifest.json\|boot.img\|vbmeta.img\)$' "$REL/SHA256SUMS" > "$REL/SHA256SUMS.new" || true
    (cd "$REL" && sha256sum manifest.json boot.img $( [ -f vbmeta.img ] && echo vbmeta.img )) >> "$REL/SHA256SUMS.new"
    mv "$REL/SHA256SUMS.new" "$REL/SHA256SUMS"
fi
echo "release-add-boot: $REL/boot.img ($SHA)"
