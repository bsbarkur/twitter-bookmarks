#!/bin/zsh
# Harvests posts from an X page open in your logged-in Chrome via the Accessibility API (no API key, no cookies).
#   scripts/harvest.sh bookmarks [max]   → data/bookmarks.jsonl   (x.com/i/history, "Bookmarks" tab, the default)
#   scripts/harvest.sh likes     [max]   → data/likes.jsonl       (x.com/i/history/likes, "Likes" tab)
# X's History page (x.com/i/history; x.com/i/bookmarks redirects there) has two tabs: Bookmarks and Likes.
# Re-running resumes: ids already in the file are skipped. Stops after ~30 s with no new posts.
# The page opens in a new Chrome window. Keep that window visible (not minimised or fully covered) while it runs:
# Chrome stops loading more posts in hidden windows.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WHAT=${1:?usage: harvest.sh bookmarks|likes [max]}
MAX=${2:-20000}
case $WHAT in
  bookmarks) URL=https://x.com/i/history ;;
  likes)     URL=https://x.com/i/history/likes ;;
  *) echo "unknown: $WHAT"; exit 1 ;;
esac
mkdir -p "$ROOT/data"
osascript -e 'on run {u}' -e 'tell application "Google Chrome"' -e 'make new window' \
  -e 'set URL of active tab of front window to u' -e 'activate' -e 'end tell' -e 'end run' "$URL"
echo "opened $URL — waiting 8 s for it to load…"; sleep 8
"$ROOT/vendor/bin/xharvest" --url="$URL" --max="$MAX" --out="$ROOT/data/$WHAT.jsonl"
wc -l "$ROOT/data/$WHAT.jsonl"
