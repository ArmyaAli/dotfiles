#!/usr/bin/env python3
"""Print the current Hacker News front page, in site order.

One story per line, tab-separated: title, url, unix time, score, comments.
Uses the official Firebase API so the order matches news.ycombinator.com.
"""
import json
import urllib.request

API = "https://hacker-news.firebaseio.com/v0"
LIMIT = 20


def get(url):
    with urllib.request.urlopen(url, timeout=8) as r:
        return json.load(r)


def main():
    try:
        ids = get(API + "/topstories.json")[:LIMIT]
    except Exception:
        return
    for item_id in ids:
        try:
            d = get(API + "/item/%d.json" % item_id)
        except Exception:
            continue
        if not d or d.get("type") != "story" or d.get("deleted") or d.get("dead"):
            continue
        title = (d.get("title") or "").replace("\t", " ").replace("\n", " ").strip()
        if not title:
            continue
        url = d.get("url") or ("https://news.ycombinator.com/item?id=%d" % item_id)
        print("%s\t%s\t%s\t%s\t%s" % (title, url, d.get("time", 0), d.get("score", 0), d.get("descendants", 0)))


if __name__ == "__main__":
    main()
