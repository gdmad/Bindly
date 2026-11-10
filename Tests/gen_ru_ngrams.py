#!/usr/bin/env python3
"""Builds the Russian seed files for Bindly's autocomplete from one or more text corpora.

Usage:
  gen_ru_ngrams.py <outdir> --source PATH[:WEIGHT] [--source PATH[:WEIGHT] ...]
                   [--exclude PATH ...] [--top-unigrams N] [--top-bigrams N] [--top-trigrams N]
                   [--min-count N]

Sources:
  *.txt      one sentence per line; a Leipzig "<id>\\t<sentence>" line drops its id
  *.parquet  a "text" column of documents (the Taiga corpus on Hugging Face); needs pyarrow
  Texts are split into sentences at . ! ? ; and line breaks, so n-grams never cross them.
  WEIGHT (default 1) is the source's share of the mixture: each source is scaled to the same
  token mass before weighting, so a small conversational corpus is not drowned by a big news one.

Shipped files (see AGENTS.md for the sources and licenses): Leipzig rus_news_2023 / rus-ru_web-public
(CC BY 4.0) and Taiga social / subtitles (CC BY-SA 3.0).

Filtering: lines with links, e-mail addresses or mostly Latin letters are dropped, as are
character floods ("ааааа"); --exclude files (the evaluator's sets) never reach the tables.
An n-gram must occur --min-count times (default 3) across all sources before it is kept; a pair or
triple seen once within one source is dropped first, and each source is read up to --max-words.

Output (tab-separated, scaled counts, sorted by count descending):
  <outdir>/ru_unigrams.txt     word \\t count                   (top N words)
  <outdir>/ru_bigrams_ctx.txt  prev \\t next \\t count           (top N bigrams)
  <outdir>/ru_trigrams.txt     prev2 \\t prev1 \\t next \\t count (top N trigrams)

Tokens: contiguous letter runs (Cyrillic + Latin), lowercased; "е" and "ё" stay distinct keys,
matching the learning store. Punctuation and numbers split tokens.
"""
import argparse
import collections
import os
import re
import sys

TOKEN_RE = re.compile(r"[^\W\d_]+", re.UNICODE)
SENTENCE_SPLIT_RE = re.compile(r"[.!?;\n\r…]+")
LINK_RE = re.compile(r"https?://|www\.|@\w|\.(ru|com|org|net)\b", re.IGNORECASE)
FLOOD_RE = re.compile(r"(\w)\1{3,}")
LATIN_RE = re.compile(r"[A-Za-z]")
CYRILLIC_RE = re.compile(r"[Ѐ-ӿ]")


def tokenize(line):
    return [t.lower() for t in TOKEN_RE.findall(line)]


def clean(sentence):
    if LINK_RE.search(sentence) or FLOOD_RE.search(sentence):
        return None
    latin = len(LATIN_RE.findall(sentence))
    cyrillic = len(CYRILLIC_RE.findall(sentence))
    if cyrillic == 0 or latin > 0.3 * (latin + cyrillic):
        return None
    words = tokenize(sentence)
    return words if len(words) >= 2 else None


def texts(path):
    if path.endswith(".parquet"):
        import pyarrow.parquet as pq
        table = pq.ParquetFile(path)
        for batch in table.iter_batches(columns=["text"], batch_size=2000):
            for text in batch.column(0).to_pylist():
                if text:
                    yield text
    else:
        with open(path, encoding="utf-8") as f:
            for line in f:
                head, sep, rest = line.partition("\t")
                yield rest if sep and head.isdigit() else line


def sentences(path):
    for text in texts(path):
        for piece in SENTENCE_SPLIT_RE.split(text):
            if piece.strip():
                yield piece


def count_source(path, excluded, max_words):
    # Keys are tab-joined strings, not tuples: a third of the memory on tens of millions of n-grams.
    uni, bi, tri = collections.Counter(), collections.Counter(), collections.Counter()
    n_sentences = n_words = 0
    for sentence in sentences(path):
        ws = clean(sentence)
        if ws is None or " ".join(ws) in excluded:
            continue
        n_sentences += 1
        n_words += len(ws)
        uni.update(ws)
        bi.update(ws[i - 1] + "\t" + ws[i] for i in range(1, len(ws)))
        tri.update(ws[i - 2] + "\t" + ws[i - 1] + "\t" + ws[i] for i in range(2, len(ws)))
        if n_words >= max_words:
            break
    # A pair seen once in a source is noise at these sizes; dropping it keeps the merge in memory.
    for table in (bi, tri):
        for key in [k for k, c in table.items() if c < 2]:
            del table[key]
    print(f"{os.path.basename(path)}: sentences={n_sentences} words={n_words}", file=sys.stderr)
    return uni, bi, tri, n_words


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("outdir")
    ap.add_argument("--source", action="append", required=True)
    ap.add_argument("--exclude", action="append", default=[])
    ap.add_argument("--top-unigrams", type=int, default=100_000)
    ap.add_argument("--top-bigrams", type=int, default=50_000)
    ap.add_argument("--top-trigrams", type=int, default=150_000)
    ap.add_argument("--min-count", type=int, default=3)
    ap.add_argument("--max-words", type=int, default=20_000_000, help="words read per source")
    args = ap.parse_args()

    excluded = set()
    for path in args.exclude:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if not line.startswith("#"):
                    for piece in SENTENCE_SPLIT_RE.split(line):
                        ws = tokenize(piece)
                        if ws:
                            excluded.add(" ".join(ws))

    sources = []
    for spec in args.source:
        path, _, weight = spec.rpartition(":") if re.search(r":[\d.]+$", spec) else (spec, "", "1")
        sources.append((path, float(weight)))

    totals = [collections.Counter(), collections.Counter(), collections.Counter()]
    raw = [collections.Counter(), collections.Counter(), collections.Counter()]
    target_mass = 10_000_000
    for path, weight in sources:
        tables = count_source(path, excluded, args.max_words)
        scale = weight * target_mass / max(1, tables[3])
        for k in range(3):
            raw[k].update(tables[k])
            for key, c in tables[k].items():
                totals[k][key] += c * scale

    def top(k, n):
        kept = ((key, c) for key, c in totals[k].items() if raw[k][key] >= args.min_count)
        return sorted(kept, key=lambda kv: (-kv[1], kv[0]))[:n]

    os.makedirs(args.outdir, exist_ok=True)
    with open(os.path.join(args.outdir, "ru_unigrams.txt"), "w", encoding="utf-8") as f:
        for w, c in top(0, args.top_unigrams):
            f.write(f"{w}\t{max(1, round(c))}\n")
    with open(os.path.join(args.outdir, "ru_bigrams_ctx.txt"), "w", encoding="utf-8") as f:
        for key, c in top(1, args.top_bigrams):
            f.write(f"{key}\t{max(1, round(c))}\n")
    with open(os.path.join(args.outdir, "ru_trigrams.txt"), "w", encoding="utf-8") as f:
        for key, c in top(2, args.top_trigrams):
            f.write(f"{key}\t{max(1, round(c))}\n")
    print(f"unique: words={len(totals[0])} bigrams={len(totals[1])} trigrams={len(totals[2])} -> {args.outdir}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
