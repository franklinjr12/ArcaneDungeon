#!/usr/bin/env bash
# AD-090: capture every UI state at every matrix resolution (run from the repo root).
set -euo pipefail

GODOT=/usr/local/bin/godot
OUT=docs/ui/matrix
STATES="title settings combat reward workshop_editor merchant pause summary"
SIZES="1280x720 1366x768 1600x900 1920x1080 2560x1440 3840x2160 1280x800 1920x1200 2560x1080 3440x1440 1024x768"

while [ $# -gt 0 ]; do
	case "$1" in
		--godot) GODOT=$2; shift 2 ;;
		--out) OUT=$2; shift 2 ;;
		--states) STATES=$2; shift 2 ;;
		--sizes) SIZES=$2; shift 2 ;;
		*) echo "usage: $0 [--godot PATH] [--out DIR] [--states \"a b\"] [--sizes \"WxH ...\"]" >&2; exit 2 ;;
	esac
done

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
REPO=$(pwd)
FAILS=0
SHOTS=0

check_png() { # png expected
	SHOTS=$((SHOTS + 1))
	if [ ! -s "$1" ]; then
		echo "FAIL missing $1"; FAILS=$((FAILS + 1)); return
	fi
	local got; got=$(identify -format %wx%h "$1")
	echo "  $1 -> $got"
	[ "$got" = "$2" ] || echo "WARN size $got != expected $2 ($1)"
}

run_shot() { # label expected_size xvfb_screen state extra_env...
	local dir=$1 expect=$2 screen=$3 state=$4 res=$5; shift 5
	local png="$OUT/$dir/$state.png" xdg rc=0
	mkdir -p "$OUT/$dir"; rm -f "$png"
	xdg=$(mktemp -d)
	echo "== $dir / $state"
	env "$@" AD_UI_SHOT_STATE="$state" AD_UI_SHOT_OUT="$png" XDG_DATA_HOME="$xdg" \
		timeout 60 xvfb-run -a -s "-screen 0 ${screen}x24" "$GODOT" --path "$REPO" --resolution "$res" \
		>"$xdg/log.txt" 2>&1 || rc=$?
	[ "$rc" -eq 0 ] || { echo "FAIL exit $rc ($dir/$state)"; tail -n 5 "$xdg/log.txt"; }
	[ "$rc" -eq 0 ] || [ -s "$png" ] || FAILS=$((FAILS + 1))
	if [ "$rc" -eq 0 ]; then check_png "$png" "$expect"; fi
	rm -rf "$xdg"
}

for state in $STATES; do
	for size in $SIZES; do
		run_shot "$size" "$size" "$size" "$state" "$size"
	done
	run_shot fullscreen_1280x720_on_1920x1080 1920x1080 1920x1080 "$state" 1280x720 AD_UI_SHOT_FULLSCREEN=1

	# live resize 1280x720 -> 1920x1080
	dir=resize_1280x720_to_1920x1080
	png="$OUT/$dir/$state.png"; mkdir -p "$OUT/$dir"; rm -f "$png"
	xdg=$(mktemp -d)
	echo "== $dir / $state"
	rc=0
	AD_UI_SHOT_STATE="$state" AD_UI_SHOT_OUT="$png" AD_UI_SHOT_DELAY_MS=3000 XDG_DATA_HOME="$xdg" \
		GODOT="$GODOT" REPO="$REPO" LOG="$xdg/log.txt" \
		timeout 90 xvfb-run -a -s "-screen 0 1920x1080x24" bash -c '
			"$GODOT" --path "$REPO" --resolution 1280x720 >"$LOG" 2>&1 &
			PID=$!
			if command -v xdotool >/dev/null; then
				WID=$(timeout 30 xdotool search --sync --pid $PID 2>/dev/null | head -n1 || true)
				if [ -n "$WID" ]; then
					sleep 1
					xdotool windowsize "$WID" 1920 1080 || echo "WARN resize failed"
				else echo "WARN no window found for resize"; fi
			else echo "WARN xdotool missing, no resize"; fi
			wait $PID
		' || rc=$?
	if [ "$rc" -ne 0 ] || [ ! -s "$png" ]; then
		echo "FAIL resize exit $rc"; tail -n 5 "$xdg/log.txt"; FAILS=$((FAILS + 1))
	else
		check_png "$png" 1920x1080
	fi
	rm -rf "$xdg"
done

# contact sheets
mkdir -p "$OUT/sheets"
for state in $STATES; do
	files=(); args=()
	for f in "$OUT"/*/"$state.png"; do
		[ -e "$f" ] || continue
		case "$f" in */sheets/*) continue ;; esac
		files+=("$f"); args+=(-label "$(basename "$(dirname "$f")")" "$f")
	done
	[ ${#files[@]} -gt 0 ] || continue
	if command -v montage >/dev/null; then
		montage "${args[@]}" -geometry 480x270+6+6 -tile 4x -background '#0b1320' -fill white "$OUT/sheets/$state.png"
	else
		python3 -I - "$OUT/sheets/$state.png" "${files[@]}" <<'PY'
import sys, os
from PIL import Image, ImageDraw
out, files = sys.argv[1], sys.argv[2:]
cols, w, h = 4, 480, 270
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (w + 12), rows * (h + 30)), "#0b1320")
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB"); im.thumbnail((w, h))
    x, y = (i % cols) * (w + 12) + 6, (i // cols) * (h + 30) + 6
    d.text((x, y), os.path.basename(os.path.dirname(f)), fill="white")
    sheet.paste(im, (x, y + 16))
sheet.save(out)
PY
	fi
	echo "sheet $OUT/sheets/$state.png (${#files[@]} images)"
done

echo "SUMMARY: $SHOTS shots, $FAILS failed"
[ "$FAILS" -eq 0 ]
