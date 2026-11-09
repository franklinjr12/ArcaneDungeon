#!/usr/bin/env bash
# AD-090: capture the UI resolution matrix (debug-only AD_UI_SHOT_* hook) and build contact sheets.
# Run from the repo root: bash tools/ui_matrix.sh [--godot PATH] [--out DIR] [--states "a b"] [--sizes "WxH ..."]
set -euo pipefail

GODOT=/usr/local/bin/godot
OUT=docs/ui/matrix
STATES="title settings credits combat reward workshop_editor merchant pause summary summary_win sigil_desk loadout compendium compendium_reactions compendium_enemies compendium_artifacts tip_room1 tip_telegraph tip_wet_try_lightning tip_first_reward tip_first_workshop tip_workshop_empty_slot tip_test_on_dummy tip_spells_are_runes pause_controls settings_access"
SIZES="1280x720 1366x768 1600x900 1920x1080 2560x1440 3840x2160 1280x800 1920x1200 2560x1080 3440x1440 1024x768"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--godot) GODOT=$2; shift 2 ;;
		--out) OUT=$2; shift 2 ;;
		--states) STATES=$2; shift 2 ;;
		--sizes) SIZES=$2; shift 2 ;;
		*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
TMPS=()
cleanup() { for d in "${TMPS[@]:-}"; do if [[ -n "$d" ]]; then rm -rf "$d"; fi; done; }
trap cleanup EXIT
fails=0
total=0

fresh_xdg() { local d; d=$(mktemp -d); TMPS+=("$d"); echo "$d"; }

check() { # png expected [soft]: soft = size mismatch is a NOTE (known Xvfb limit), not a WARN
	local png=$1 expect=$2
	total=$((total + 1))
	if [[ ! -s "$png" ]]; then
		echo "FAIL missing $png"; fails=$((fails + 1)); return
	fi
	local got; got=$(identify -format %wx%h "$png" 2>/dev/null || echo unknown)
	echo "  $png -> $got"
	[[ "$got" == "$expect" ]] && return
	if [[ "${3:-}" == soft ]]; then
		echo "NOTE $png is $got, not $expect: fullscreen has no effect under Xvfb without a window manager"
	else
		echo "WARN $png is $got, expected $expect"
	fi
}

for size in $SIZES; do
	W=${size%x*}; H=${size#*x}
	mkdir -p "$OUT/$size"
	for state in $STATES; do
		png="$OUT/$size/$state.png"; rm -f "$png"
		echo "== $size $state"
		AD_UI_SHOT_STATE=$state AD_UI_SHOT_OUT=$png XDG_DATA_HOME=$(fresh_xdg) \
			timeout 60 xvfb-run -a -s "-screen 0 ${W}x${H}x24" "$GODOT" --path . --resolution "$size" >/dev/null 2>&1 \
			|| { echo "FAIL exit $size $state"; fails=$((fails + 1)); continue; }
		check "$png" "$size"
	done
done

# Fullscreen toggle: 1280x720 window on a 1920x1080 screen.
FS=fullscreen_1280x720_on_1920x1080
mkdir -p "$OUT/$FS"
for state in $STATES; do
	png="$OUT/$FS/$state.png"; rm -f "$png"
	echo "== $FS $state"
	AD_UI_SHOT_STATE=$state AD_UI_SHOT_OUT=$png AD_UI_SHOT_FULLSCREEN=1 XDG_DATA_HOME=$(fresh_xdg) \
		timeout 60 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --resolution 1280x720 >/dev/null 2>&1 \
		|| { echo "FAIL exit $FS $state"; fails=$((fails + 1)); continue; }
	check "$png" 1920x1080 soft
done

# Live resize: 1280x720 -> 1920x1080 via xdotool after launch.
RS=resize_1280x720_to_1920x1080
mkdir -p "$OUT/$RS"
for state in $STATES; do
	png="$OUT/$RS/$state.png"; rm -f "$png"
	echo "== $RS $state"
	export GODOT AD_UI_SHOT_STATE=$state AD_UI_SHOT_OUT=$png AD_UI_SHOT_DELAY_MS=3000 XDG_DATA_HOME=$(fresh_xdg)
	timeout 60 xvfb-run -a -s "-screen 0 1920x1080x24" bash -c '
		"$GODOT" --path . --resolution 1280x720 >/dev/null 2>&1 &
		PID=$!
		if command -v xdotool >/dev/null; then
			WID=$(timeout 20 xdotool search --sync --pid $PID 2>/dev/null | head -1 || true)
			if [[ -n "$WID" ]]; then
				sleep 1
				xdotool windowsize "$WID" 1920 1080 || echo "WARN xdotool resize failed"
			else
				echo "WARN no window found for resize"
			fi
		else
			echo "WARN xdotool missing; resize skipped"
		fi
		wait $PID
	' || { echo "FAIL exit $RS $state"; fails=$((fails + 1)); continue; }
	check "$png" 1920x1080
done
unset AD_UI_SHOT_STATE AD_UI_SHOT_OUT AD_UI_SHOT_DELAY_MS

# Contact sheets per state.
mkdir -p "$OUT/sheets"
for state in $STATES; do
	files=()
	while IFS= read -r f; do files+=(-label "$(basename "$(dirname "$f")")" "$f"); done \
		< <(find "$OUT" -mindepth 2 -maxdepth 2 -name "$state.png" -not -path "$OUT/sheets/*" | sort)
	[[ ${#files[@]} -gt 0 ]] || continue
	if command -v montage >/dev/null; then
		montage -pointsize 14 "${files[@]}" -geometry 480x270+6+6 -tile 4x -background '#0b1320' -fill white "$OUT/sheets/$state.png"
	else
		python3 -I - "$OUT/sheets/$state.png" "${files[@]}" <<'PY'
import sys
from PIL import Image, ImageDraw
out, args = sys.argv[1], sys.argv[2:]
items = [(args[i + 1], args[i + 2]) for i in range(0, len(args), 3)]
cols, tw, th = 4, 480, 270
rows = (len(items) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (tw + 12), rows * (th + 30)), "#0b1320")
d = ImageDraw.Draw(sheet)
for n, (label, path) in enumerate(items):
    im = Image.open(path).convert("RGB"); im.thumbnail((tw, th))
    x, y = (n % cols) * (tw + 12) + 6, (n // cols) * (th + 30) + 6
    sheet.paste(im, (x, y + 18)); d.text((x, y), label, fill="white")
sheet.save(out)
PY
	fi
	echo "sheet $OUT/sheets/$state.png"
done

echo "SUMMARY: $total shots, $fails failed"
[[ $fails -eq 0 ]]
