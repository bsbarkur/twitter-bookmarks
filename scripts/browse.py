"""Builds data/browse.html: one self-contained page to search and browse every harvested post with its topics.

    python3 scripts/browse.py            # reads data/<source>.jsonl (+ data/<source>.topics.jsonl when sorted)

Sources are bookmarks and likes. Posts keep X's order: each harvest run lists its new posts newest first, and later
runs sit above earlier ones.
"""
import datetime
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
SOURCES = ["bookmarks", "likes"]
MONTHS = {m: i for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(), 1)}


def parse_iso(stamp):
    return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00")) if stamp else None


def post_date(created, harvested):
    """X shows "Nov 13, 2024", "Oct 9" (this year) or "11 hours ago"; returns an ISO date or None."""
    created = created.strip()
    if match := re.fullmatch(r"([A-Z][a-z]{2}) (\d{1,2}), (\d{4})", created):
        return datetime.date(int(match[3]), MONTHS[match[1]], int(match[2])).isoformat()
    if not harvested:
        return None
    if match := re.fullmatch(r"([A-Z][a-z]{2}) (\d{1,2})", created):
        day = datetime.date(harvested.year, MONTHS[match[1]], int(match[2]))
        return (day if day <= harvested.date() else day.replace(year=day.year - 1)).isoformat()
    if re.fullmatch(r"\d+ (second|minute|hour)s? ago|\d+[smh]|now", created):
        return harvested.date().isoformat()
    return None


def clean(text):
    """Drops the bare "Replying to" line the accessibility tree leaves when it skips the @mention links."""
    reply = text.startswith("Replying to")
    if reply:
        text = text[len("Replying to"):].lstrip()
    return re.sub(r"\n{2,}", "\n\n", text).strip(), reply


def load(source):
    path = DATA / f"{source}.jsonl"
    if not path.exists():
        return []
    rows = [json.loads(line) for line in path.open() if line.strip()]
    topics = {}
    topic_path = DATA / f"{source}.topics.jsonl"
    if topic_path.exists():
        for line in topic_path.open():
            if line.strip():
                row = json.loads(line)
                topics[row[0]] = row[1:]
    # Newest run first; inside a run, page order (X lists newest first).
    runs = sorted({r.get("harvestedAt") or "" for r in rows}, reverse=True)
    run_rank = {run: i for i, run in enumerate(runs)}
    order = sorted(range(len(rows)), key=lambda i: (run_rank[rows[i].get("harvestedAt") or ""], i))
    posts = []
    for rank, i in enumerate(order):
        r = rows[i]
        harvested = parse_iso(r.get("harvestedAt"))
        text, reply = clean(r.get("text", ""))
        path_names = topics.get(r["id"], [])
        posts.append({
            "id": r["id"],
            "a": r.get("author", ""),
            "t": text,
            "r": int(reply),
            "c": r.get("createdAt", ""),
            "d": post_date(r.get("createdAt", ""), harvested),
            "m": sorted(set(r.get("media", []))),
            "s": source,
            "o": rank,
            "h": r.get("harvestedAt"),
            "tp": path_names[0] if path_names else "Unsorted",
            "st": path_names[1] if len(path_names) > 1 else "",
        })
    return posts


def main():
    posts = [p for source in SOURCES for p in load(source)]
    payload = {
        "posts": posts,
        "built": datetime.datetime.now().astimezone().strftime("%d %b %Y, %H:%M"),
    }
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    template = (ROOT / "scripts" / "browse.template.html").read_text()
    out = DATA / "browse.html"
    out.write_text(template.replace("/*__DATA__*/null", data))
    counts = ", ".join(f"{sum(p['s'] == s for p in posts)} {s}" for s in SOURCES)
    print(f"browse → {out} ({counts})")


if __name__ == "__main__":
    main()
