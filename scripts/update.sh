#!/bin/zsh
# Pulls new bookmarks and likes, re-sorts everything into topics and rebuilds data/browse.html.
# Each harvest adds only posts it hasn't seen (stopping ~30 s after the last new one); nothing is ever removed.
# Leave the Chrome window it opens visible until both harvests finish.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/harvest.sh" bookmarks
"$ROOT/scripts/harvest.sh" likes
"$ROOT/scripts/sort.sh" bookmarks 10
pkill -f "release/TopicSortDemo" 2>/dev/null || true
"$ROOT/scripts/sort.sh" likes 6
pkill -f "release/TopicSortDemo" 2>/dev/null || true
open "$ROOT/data/browse.html"
