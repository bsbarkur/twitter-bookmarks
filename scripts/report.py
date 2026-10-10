"""Joins harvested posts with the sorter's dump (["id", topic, subtopic?] per line) into a Markdown report."""
import json
import sys
from collections import defaultdict

posts_path, dump_path = sys.argv[1], sys.argv[2]
posts = {}
for line in open(posts_path):
    if line.strip():
        p = json.loads(line)
        posts[p["id"]] = p

tree = defaultdict(lambda: defaultdict(list))
for line in open(dump_path):
    if line.strip():
        row = json.loads(line)
        post_id, path = row[0], row[1:]
        tree[path[0] if path else "Unsorted"][path[1] if len(path) > 1 else ""].append(post_id)

print(f"# Topics ({len(posts)} posts)\n")
for topic, subs in sorted(tree.items(), key=lambda kv: -sum(map(len, kv[1].values()))):
    print(f"## {topic} ({sum(map(len, subs.values()))})\n")
    for sub, ids in sorted(subs.items(), key=lambda kv: -len(kv[1])):
        if sub:
            print(f"### {sub} ({len(ids)})\n")
        for post_id in ids:
            p = posts.get(post_id, {})
            text = " ".join(p.get("text", "").split())[:200]
            print(f"- [@{p.get('author', '?')}](https://x.com/{p.get('author', 'i')}/status/{post_id}) {text}")
        print()
