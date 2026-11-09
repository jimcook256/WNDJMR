# ================================================================================
# SCRIPT NAME: TECH-247812_Doc_Consistency_Check_V1.py
# TICKET ID:   TECH-247812  (builds on TECH-231527)
# AUTHOR:      Jim Cook (BI Group)
# VERSION:     v1.0
# CREATED:     2026-11-09
# PURPOSE:     Cross-check the Manhattan documentation set against itself and
#              against the stored-procedure source, so the technical document is
#              built on statements that agree. Read-only: it only reads files.
#
# WHAT IT CHECKS
#   1. FACTS     Same fact stated differently across documents (sproc count,
#                copy window, Tractor Fleet status, append vs replace, window type,
#                stale figures). Each conflicting statement is printed with its file.
#   2. JOINS     "what feeds what": join type and key pairs stated in each document
#                (the SKILL.md spine and "Joined on ..." lines in the Word docs).
#                Flags the same key given different join types or partners.
#   3. TIMELINE  Parses the mermaid timeline: date formats, chronological order,
#                and ticket ids that appear in no other document. With --sprocs it
#                also looks for each dated entry in the sproc comment logs.
#
# LIMITS
#   - It finds what documents STATE, not what is true. A conflict can be history
#     (a statement that was right when written). A human decides which is current.
#   - Regex based. A fact written in words the patterns do not cover is not seen.
#
# USAGE
#   python3 -I TECH-247812_Doc_Consistency_Check_V1.py --docs <folder> \
#           [--sprocs <folder of .sql>] [--out <report.md>]
#   --docs   folder holding .docx, .md and .txt files (copied there, not in place)
#   --sprocs folder holding sproc scripts, e.g. a clone of the MANH repo
# ================================================================================
import argparse
import datetime as dt
import os
import re
import sys
import zipfile
from collections import defaultdict


# ----------------------------------------------------------------------------- IO
def read_docx(path):
    """Text of a .docx, one line per paragraph or table row (cells joined by ' | ')."""
    import xml.etree.ElementTree as ET
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    with zipfile.ZipFile(path) as z:
        root = ET.fromstring(z.read("word/document.xml"))
    out = []
    body = root.find("w:body", ns)

    def para_text(p):
        return "".join(t.text or "" for t in p.iter("{%s}t" % ns["w"]))

    for el in body:
        tag = el.tag.split("}")[1]
        if tag == "p":
            out.append(para_text(el))
        elif tag == "tbl":
            for tr in el.iter("{%s}tr" % ns["w"]):
                cells = [para_text(tc) for tc in tr.iter("{%s}tc" % ns["w"])]
                out.append(" | ".join(cells))
    return "\n".join(out)


def load_docs(folder):
    docs = {}
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        low = name.lower()
        try:
            if low.endswith(".docx"):
                docs[name] = read_docx(path)
            elif low.endswith((".md", ".txt")):
                with open(path, encoding="utf-8", errors="replace") as f:
                    docs[name] = f.read()
        except Exception as e:  # keep going; report the unreadable file
            print("WARN could not read %s: %s" % (name, e), file=sys.stderr)
    return docs


def snippet(text, m, width=70):
    a, b = max(0, m.start() - width), min(len(text), m.end() + width)
    return " ".join(text[a:b].split())


# ------------------------------------------------------------------- 1. FACT CHECK
# label -> regex. A fact CONFLICTS when documents carry more than one label.
FACTS = {
    "Feeder sproc count": {
        "14": r"\b14\s+(?:unique\s+)?feeder\s+sprocs?|\b14\s+named\b",
        "16": r"\b16\s+(?:feeder\s+)?(?:sprocs?|entries)|\b\d+\s+of\s+16\s+feeder|\b11\s+of\s+16\b",
    },
    "Sprocs read line by line": {
        "5 read / 9 unread": r"\b5\s+have\s+been\s+read|\b9\s+(?:unread|are\s+described)",
        "5 read / 11 unread": r"\b11\s+of\s+16\s+feeder\s+sprocs\s+unread",
    },
    "Days from completion to copy": {
        "15 days": r"\b15\s+days?\s+(?:after|post)|\b11d\s+to\s+15d|15d\s+Aging",
        "about two weeks": r"about\s+two\s+weeks",
    },
    "Tractor Fleet fix status": {
        "in progress": r"In\s+Progress|CURRENT\s+WORK|Planned\s+fix",
        "applied in View": r"correction\s+was\s+applied\s+in\s+this\s+DataSet\s+View|corrected\s+in\s+the\s+View",
    },
    "Tractor Fleet leg rule": {
        "first leg": r"first\s+leg",
        "majority miles": r"majority\s+miles",
        "leg the order tractor ran": r"leg\s+that\s+tractor\s+ran|leg\s+the\s+order\s+tractor",
    },
    "Load mode into DOMO": {
        "append": r"monthly\s+append",
        "replace / full reload": r"\bREPLACE\b|full[- ]reload|fully\s+reloaded",
    },
    "Order-header window": {
        "rolling 24 months": r"rolling\s+2-?y(?:ea)?r",
        "calendar-year cutoff": r"calendar[- ]year\s+jump|Jan(?:uary)?\s+1\s+(?:of\s+)?two\s+calendar\s+years|every\s+Jan\s+1",
    },
    "Stale-figure watch": {
        "57 corrections": r"\b57\s+corrections",
        "1,652 stale values": r"1,652\s+stale",
    },
    "Run size tested": {
        "2,314 orders": r"2,314",
    },
}


def check_facts(docs):
    lines, conflicts = [], 0
    for fact, labels in FACTS.items():
        hits = defaultdict(list)  # label -> [(doc, snippet)]
        for doc, text in docs.items():
            for label, rx in labels.items():
                m = re.search(rx, text, re.I)
                if m:
                    hits[label].append((doc, snippet(text, m)))
        if not hits:
            continue
        flag = "CONFLICT" if len(hits) > 1 else "consistent"
        conflicts += flag == "CONFLICT"
        lines.append("### %s: %s" % (fact, flag))
        for label, items in hits.items():
            lines.append("- **%s**" % label)
            for doc, snip in items:
                lines.append("  - `%s`: ...%s..." % (doc, snip))
        lines.append("")
    return lines, conflicts


# ------------------------------------------------------------------- 2. JOIN CHECK
JT = r"(FULL\s+OUTER|LEFT\s+OUTER|INNER)"
SPINE_RX = re.compile(r"(Join\s+[A-Za-z0-9_ ]+?)\s+" + JT + r"\s+(.+?)\s*$", re.I | re.M)
JOINED_RX = re.compile(r"Joined\s+on\s+(.+?)\s*=\s*(.+?),\s*" + JT, re.I)


def norm(s):
    return re.sub(r"\s+", " ", s.strip().strip("`").strip()).lower()


def check_joins(docs):
    """Collect (left key, right key, join type) statements and compare across docs."""
    stated = []  # (doc, label, left, right, jtype)
    for doc, text in docs.items():
        for m in SPINE_RX.finditer(text):
            key = m.group(3)
            if "=" in key:
                left, right = [norm(x) for x in key.split("=", 1)]
                stated.append((doc, norm(m.group(1)), left, right, norm(m.group(2))))
        for m in JOINED_RX.finditer(text):
            stated.append((doc, "prose", norm(m.group(1)), norm(m.group(2)), norm(m.group(3))))
    by_pair = defaultdict(set)
    for doc, label, left, right, jt in stated:
        by_pair[(left, right)].add((jt, doc))
    by_left = defaultdict(set)
    for doc, label, left, right, jt in stated:
        by_left[left].add((right, jt, doc))
    lines, conflicts = [], 0
    lines.append("### Join statements found: %d" % len(stated))
    for (left, right), vals in sorted(by_pair.items()):
        types = {v[0] for v in vals}
        flag = "CONFLICT (join type)" if len(types) > 1 else "ok"
        conflicts += len(types) > 1
        docs_ = ", ".join(sorted({"`%s`" % v[1] for v in vals}))
        lines.append("- `%s = %s` : %s : %s [%s]" % (left, right, "/".join(sorted(types)), flag, docs_))
    lines.append("")
    lines.append("### Same left key matched to different partners (informational: expected for the order key, see Gotcha #2)")
    found = False
    for left, vals in sorted(by_left.items()):
        partners = {v[0] for v in vals}
        if len(partners) > 1:
            found = True
            lines.append("- `%s` is joined to: %s" % (left, "; ".join(sorted(partners))))
    if not found:
        lines.append("- none")
    lines.append("")
    return lines, conflicts


# ------------------------------------------------------------------ 3. TIMELINE
ENTRY_RX = re.compile(r"^\s*(\d{4}(?:-\d{2})?(?:-\d{2})?(?:/\d{2})?)\s*:\s*(.+)$")
TICKET_RX = re.compile(r"\b(TECH-\d+|CSD-\d+|#\d{4,6})\b")


def parse_date(token):
    """Return the first day of the earliest period named, or None if unparseable."""
    t = token.split("/")[0]
    for fmt in ("%Y-%m-%d", "%Y-%m", "%Y"):
        try:
            return dt.datetime.strptime(t, fmt).date()
        except ValueError:
            pass
    return None


def timeline_entries(docs):
    out = []
    for doc, text in docs.items():
        in_block = False
        for line in text.splitlines():
            if line.strip().startswith("```mermaid"):
                in_block = True
                continue
            if in_block and line.strip().startswith("```"):
                in_block = False
            if in_block:
                m = ENTRY_RX.match(line)
                if m:
                    out.append((doc, m.group(1), m.group(2).strip()))
    return out


def date_variants(token):
    """Ways a date is written in sproc comments (m/d/yy, m/d/yyyy, yyyy-mm-dd, ...)."""
    d = parse_date(token)
    if d is None or len(token.split("/")[0]) < 10:
        return []
    return [
        d.strftime("%Y-%m-%d"),
        "%d/%d/%d" % (d.month, d.day, d.year),
        "%d/%d/%02d" % (d.month, d.day, d.year % 100),
        "%02d/%02d/%d" % (d.month, d.day, d.year),
        "%02d/%02d/%02d" % (d.month, d.day, d.year % 100),
    ]


def load_sprocs(folder):
    corpus = {}
    for root, _, files in os.walk(folder):
        for f in files:
            if f.lower().endswith(".sql"):
                p = os.path.join(root, f)
                with open(p, encoding="utf-8", errors="replace") as fh:
                    corpus[os.path.relpath(p, folder)] = fh.read()
    return corpus


def check_timeline(docs, sprocs):
    entries = timeline_entries(docs)
    lines, problems = [], 0
    if not entries:
        return ["No mermaid timeline found."], 0
    other_text = {d: t for d, t in docs.items()}
    lines.append("### Entries parsed: %d (from %s)" % (len(entries), ", ".join(sorted({e[0] for e in entries}))))
    prev = None
    for doc, token, text in entries:
        d = parse_date(token)
        notes = []
        if d is None:
            notes.append("unparseable date")
        elif prev and d < prev:
            notes.append("out of order (after %s)" % prev)
        if d:
            prev = d
        for tid in TICKET_RX.findall(text):
            seen_elsewhere = [n for n, t in other_text.items() if n != doc and tid in t]
            if not seen_elsewhere:
                notes.append("%s appears in no other document" % tid)
        # Only vendor-era entries (before the DOMO import began 2021-10-11) cite sproc comment logs.
        if sprocs is not None and d and d < dt.date(2021, 10, 11):
            variants = date_variants(token)
            ids = TICKET_RX.findall(text)
            found = []
            for fn, body in sprocs.items():
                if any(v in body for v in variants) or any(i in body for i in ids):
                    found.append(fn)
            if variants or ids:
                notes.append("in sproc source: %s" % (", ".join(sorted(found)[:3]) if found else "NOT FOUND"))
                if not found:
                    problems += 1
        problems += bool([n for n in notes if "unparseable" in n or "out of order" in n or "no other document" in n])
        lines.append("- `%s` %s%s" % (token, text[:70], ("  <- " + "; ".join(notes)) if notes else ""))
    lines.append("")
    return lines, problems


# ------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__ or "")
    ap.add_argument("--docs", required=True)
    ap.add_argument("--sprocs")
    ap.add_argument("--out")
    a = ap.parse_args()

    docs = load_docs(a.docs)
    sprocs = load_sprocs(a.sprocs) if a.sprocs else None
    report = ["# Manhattan documentation consistency report", "",
              "Documents read: %d (%s)" % (len(docs), ", ".join(docs)), "",
              "Sproc files read: %s" % ("not supplied (timeline not checked against source)" if sprocs is None else len(sprocs)), ""]

    report.append("## 1. Facts stated differently across documents")
    fl, fc = check_facts(docs)
    report += fl
    report.append("## 2. What feeds what: join types and keys")
    jl, jc = check_joins(docs)
    report += jl
    report.append("## 3. Timeline")
    tl, tc = check_timeline(docs, sprocs)
    report += tl
    report.append("## Summary: %d fact conflicts, %d join issues, %d timeline entries to review" % (fc, jc, tc))
    text = "\n".join(report)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
        print("wrote", a.out)
    print(text)
    return 1 if (fc or jc or tc) else 0


if __name__ == "__main__":
    sys.exit(main())
