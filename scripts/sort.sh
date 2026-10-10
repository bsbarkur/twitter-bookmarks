#!/bin/zsh
# Sorts a harvested file into topics with EmbeddingGemma 2 on the Neural Engine (opens the SwiftUI app).
#   scripts/sort.sh bookmarks [topics=8]  → data/bookmarks.topics.jsonl + data/bookmarks.topics.md + .png
# Splits every topic into subtopics. Log (with posts/s): $TMPDIR/topic-sort-demo.log
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WHAT=${1:?usage: sort.sh bookmarks|likes [topics]}
TOPICS=${2:-8}
D="$ROOT/data"
cd "$ROOT/vendor/FluidUse"
LOG=${TMPDIR:-/tmp}/topic-sort-demo.log
: > "$LOG"
rm -f "$D/$WHAT.topics.jsonl"
.build/release/TopicSortDemo --posts="$D/$WHAT.jsonl" --topics="$TOPICS" --autostart --split-all \
  --dump="$D/$WHAT.topics.jsonl" --snapshot="$D/$WHAT.topics.png" > "$LOG" 2>&1 &
PID=$!
echo "sorter pid $PID · log $LOG — waiting for $D/$WHAT.topics.jsonl (first launch compiles the model, ~2-3 min)"
until [[ -s "$D/$WHAT.topics.jsonl" ]]; do sleep 2; kill -0 $PID 2>/dev/null || { cat "$LOG"; exit 1; }; done
sleep 2
grep -E "model loaded|posts/s" "$LOG" | sed 's/\x1b\[[0-9;]*m//g' | tail -3
python3 "$ROOT/scripts/report.py" "$D/$WHAT.jsonl" "$D/$WHAT.topics.jsonl" > "$D/$WHAT.topics.md"
python3 "$ROOT/scripts/browse.py"
echo "report → $D/$WHAT.topics.md (app is still open for browsing; quit it when done)"
