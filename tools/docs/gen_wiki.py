#!/usr/bin/env python3
"""Render docs/ into GitHub wiki pages.

The wiki is a generated copy of the docs site, rebuilt on every docs push to
main, so docs/ stays the only place pages are written. GitHub's wiki is flat
and renders plain GitHub Markdown, so this flattens the tree into page names,
turns the nav into _Sidebar.md, rewrites links and anchors, and replaces the
zensical-only syntax (admonitions, tabs, heading ids, front matter).

Usage: gen_wiki.py OUT_DIR [--repo owner/name] [--ref sha]
Run tools/docs/gen_api_reference.py first; the reference pages are generated.
"""

import argparse
import os
import re
import shutil
import sys
import tomllib
import unicodedata
from pathlib import Path, PurePosixPath
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"

FENCE = re.compile(r"^(\s*)(`{3,}|~{3,})")
ADMONITION = re.compile(r'^(\s*)(?:!!!|\?\?\?\+?)\s+([A-Za-z-]+)(?:\s+"(.*)")?\s*$')
TAB = re.compile(r'^(\s*)===\+?\s+"(.*)"\s*$')
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
HEADING_ID = re.compile(r"\s*\{\s*#([\w-]+)[^}]*\}\s*$")
LINK = re.compile(r"(!?)\[((?:[^\[\]]|\[[^\]]*\])*)\]\(([^)\s]+)((?:\s+\"[^\"]*\")?)\)")

ALERT = {
    "note": "NOTE", "info": "NOTE", "abstract": "NOTE", "summary": "NOTE", "example": "NOTE", "quote": "NOTE",
    "tip": "TIP", "hint": "TIP", "success": "TIP", "check": "TIP", "done": "TIP",
    "important": "IMPORTANT", "question": "IMPORTANT", "help": "IMPORTANT", "faq": "IMPORTANT",
    "warning": "WARNING", "caution": "WARNING", "attention": "WARNING",
    "danger": "CAUTION", "error": "CAUTION", "failure": "CAUTION", "fail": "CAUTION", "bug": "CAUTION",
}


def zensical_slug(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^\w\s-]", "", text).strip().lower()
    return re.sub(r"[-\s]+", "-", text)


def github_slug(text: str) -> str:
    text = re.sub(r"[^\w\- ]", "", text.lower())
    return text.replace(" ", "-")


def plain(text: str) -> str:
    """Heading text as rendered: no link targets, code ticks or emphasis."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"[`*_]", "", text)


def code_spans(text: str) -> list[tuple[int, int]]:
    """CommonMark's rule: a run of n backticks closes on the next run of
    exactly n; a run with no partner is literal text."""
    runs = [(m.start(), m.end()) for m in re.finditer(r"`+", text)]
    spans, i = [], 0
    while i < len(runs):
        start, end = runs[i]
        partner = next((j for j in range(i + 1, len(runs)) if runs[j][1] - runs[j][0] == end - start), None)
        if partner is None:
            i += 1
            continue
        spans.append((start, runs[partner][1]))
        i = partner + 1
    return spans


def unique(slug: str, seen: dict[str, int], sep: str) -> str:
    if slug not in seen:
        seen[slug] = 0
        return slug
    seen[slug] += 1
    return f"{slug}{sep}{seen[slug]}"


# Page names

def nav_entries(nav, trail=()):
    """(path, title, trail) per page, in nav order. An untitled entry is the
    index of the section it sits in and takes the section's name."""
    for item in nav:
        if isinstance(item, str):
            yield item, trail[-1] if trail else None, trail
            continue
        (title, value), = item.items()
        if isinstance(value, str):
            yield value, title, trail
        else:
            yield from nav_entries(value, trail + (title,))


def page_name(title: str) -> str:
    title = title.replace("&", "and")
    title = re.sub(r"[^\w ()\-]", "", title)
    return re.sub(r"\s+", " ", title).strip(" -")


def first_heading(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        m = HEADING.match(line)
        if m and len(m.group(1)) == 1:
            return plain(HEADING_ID.sub("", m.group(2)))
    return path.stem


def assign_names(nav) -> tuple[dict[str, str], list]:
    entries = list(nav_entries(nav))
    names: dict[str, str] = {}
    taken: set[str] = set()

    def key(name: str) -> str:
        # Two titles are one page when they share a file name: GitHub writes
        # spaces as hyphens and a checkout may ignore case.
        return name.replace(" ", "-").lower()

    def claim(path: str, title: str, trail: tuple):
        base = "Home" if path == "index.md" else page_name(title)
        name = base
        for section in reversed(trail):
            if key(name) not in taken:
                break
            name = f"{base} ({page_name(section)})"
        n = 2
        while key(name) in taken:
            name = f"{base} ({n})"
            n += 1
        taken.add(key(name))
        names[path] = name

    for path, title, trail in entries:
        claim(path, title or first_heading(DOCS / path), trail)
    # Pages the nav leaves out are still linked from others, and take the
    # section names of the nav pages beside them.
    trails = {str(PurePosixPath(p).parent): t for p, _, t in entries}
    for md in sorted(DOCS.rglob("*.md")):
        rel = md.relative_to(DOCS).as_posix()
        if rel not in names:
            parent = str(PurePosixPath(rel).parent)
            claim(rel, first_heading(md), trails.get(parent, tuple(PurePosixPath(parent).parts)))
    return names, entries


# Anchors

def anchors(path: Path) -> dict[str, str]:
    """Each anchor zensical gives a heading, mapped to the one GitHub gives it."""
    out: dict[str, str] = {}
    z_seen: dict[str, int] = {}
    g_seen: dict[str, int] = {}
    in_fence = None
    for line in path.read_text(encoding="utf-8").splitlines():
        f = FENCE.match(line)
        if f:
            mark = f.group(2)[0]
            if in_fence is None:
                in_fence = mark
            elif in_fence == mark:
                in_fence = None
            continue
        if in_fence:
            continue
        m = HEADING.match(line)
        if not m:
            continue
        raw = m.group(2)
        explicit = HEADING_ID.search(raw)
        text = plain(HEADING_ID.sub("", raw))
        g = unique(github_slug(text), g_seen, "-")
        z = explicit.group(1) if explicit else unique(zensical_slug(text), z_seen, "_")
        out[z] = g
        out.setdefault(zensical_slug(text), g)
    return out


# Conversion

class Converter:
    def __init__(self, names, repo, ref):
        self.names = names
        self.repo = repo
        self.ref = ref
        self.anchor_maps = {p: anchors(DOCS / p) for p in names}
        self.problems: list[str] = []

    def blob(self, rel: str, raw: bool) -> str:
        if raw:
            return f"https://raw.githubusercontent.com/{self.repo}/{self.ref}/docs/{rel}"
        return f"https://github.com/{self.repo}/blob/{self.ref}/docs/{rel}"

    def target(self, page: str, url: str, image: bool) -> str:
        if re.match(r"^[a-z][a-z0-9+.-]*:", url, re.I) or url.startswith("//"):
            return url
        path, _, fragment = url.partition("#")
        if not path:
            dest = page
        else:
            dest = os.path.normpath(os.path.join(os.path.dirname(page), path)).replace(os.sep, "/")
            if dest.endswith("/") or (DOCS / dest).is_dir():
                dest = dest.rstrip("/") + "/index.md"
        if not dest.endswith(".md"):
            if not (DOCS / dest).exists() and not dest.startswith("api/reference/"):
                self.problems.append(f"{page}: link to missing file {url}")
            return self.blob(dest, raw=image) + (f"#{fragment}" if fragment else "")
        if dest not in self.names:
            self.problems.append(f"{page}: link to missing page {url}")
            return url
        anchor = ""
        if fragment:
            mapped = self.anchor_maps[dest].get(fragment)
            if mapped is None:
                self.problems.append(f"{page}: unknown anchor {url}")
                mapped = github_slug(fragment)
            anchor = f"#{mapped}"
        if dest == page and anchor:
            return anchor
        return quote(self.names[dest].replace(" ", "-")) + anchor

    def inline(self, page: str, text: str) -> str:
        """Rewrites a run of prose lines at once: link text may wrap a line."""
        lines = []
        for line in text.split("\n"):
            m = HEADING.match(line)
            lines.append(f"{m.group(1)} {HEADING_ID.sub('', m.group(2))}" if m else line)
        text = "\n".join(lines)

        # A link shown inside inline code is literal text, but code inside a
        # link's own text is not, so only a link starting in code is kept.
        code = code_spans(text)

        def link(m):
            if any(a <= m.start() < b for a, b in code):
                return m.group(0)
            bang, label, url, title = m.groups()
            return f"{bang}[{label}]({self.target(page, url, bool(bang))}{title})"

        return LINK.sub(link, text)

    def blocks(self, page: str, lines: list[str]) -> list[str]:
        out: list[str] = []
        prose: list[str] = []

        def flush():
            if prose:
                out.extend(self.inline(page, "\n".join(prose)).split("\n"))
                prose.clear()

        i = 0
        while i < len(lines):
            line = lines[i]
            f = FENCE.match(line)
            if f or ADMONITION.match(line) or TAB.match(line):
                flush()
            if f:
                indent, mark = f.groups()
                out.append(line)
                i += 1
                while i < len(lines):
                    out.append(lines[i])
                    close = FENCE.match(lines[i])
                    i += 1
                    if close and close.group(2)[0] == mark[0] and len(close.group(2)) >= len(mark) and lines[i - 1].strip() == close.group(2):
                        break
                continue

            a = ADMONITION.match(line)
            t = None if a else TAB.match(line)
            if a or t:
                indent = (a or t).group(1)
                body, i = self.body(lines, i + 1, len(indent) + 4)
                inner = self.blocks(page, body)
                while inner and not inner[-1].strip():
                    inner.pop()
                if a:
                    kind, title = a.group(2).lower(), a.group(3)
                    quoted = [f"[!{ALERT.get(kind, 'NOTE')}]"]
                    if title:
                        quoted.append(f"**{title}**")
                        if inner:
                            quoted.append("")
                    quoted += inner
                    out += [indent + ("> " + q if q else ">") for q in quoted]
                else:
                    out += [f"{indent}**{t.group(2)}**", ""]
                    out += [(indent + q if q else "") for q in inner]
                out.append("")
                continue

            prose.append(line)
            i += 1
        flush()
        return out

    @staticmethod
    def body(lines: list[str], i: int, width: int) -> tuple[list[str], int]:
        body: list[str] = []
        while i < len(lines):
            line = lines[i]
            if line.strip() and len(line) - len(line.lstrip(" ")) < width:
                break
            body.append(line[width:] if line.strip() else "")
            i += 1
        while body and not body[-1]:
            body.pop()
        return body, i

    def page(self, rel: str) -> str:
        text = (DOCS / rel).read_text(encoding="utf-8")
        text = re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.S)
        lines = self.blocks(rel, text.splitlines())
        return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip() + "\n"


LEFTOVERS = [
    (re.compile(r"^\s*(?:!!!|\?\?\?)"), "admonition"),
    (re.compile(r'^\s*===\+?\s+"'), "tab"),
    (re.compile(r"^#{1,6} .*\{\s*#[\w-]+"), "heading id"),
    (re.compile(r"\]\((?![a-z][a-z0-9+.-]*:)[^)\s]*\.md(?:#[^)\s]*)?\)", re.I), "unconverted link"),
]


def leftovers(name: str, text: str) -> list[str]:
    """What the conversion missed: a link it never matched raises no warning
    of its own, so the output is checked for anything still zensical-shaped."""
    found, fence = [], None
    for n, line in enumerate(text.splitlines(), 1):
        f = FENCE.match(line)
        if f:
            fence = None if fence == f.group(2)[0] else (fence or f.group(2)[0])
            continue
        if fence:
            continue
        for pattern, what in LEFTOVERS:
            if pattern.search(line):
                found.append(f"{name}:{n}: {what} left: {line.strip()[:80]}")
    return found


def sidebar(nav, names) -> str:
    out = []

    def walk(items, depth):
        for item in items:
            if isinstance(item, str):
                continue  # A section's index is linked from the section's own line.
            (title, value), = item.items()
            pad = "  " * depth
            if isinstance(value, str):
                out.append(f"{pad}- [{title}]({quote(names[value].replace(' ', '-'))})")
                continue
            index = next((v for v in value if isinstance(v, str)), None)
            label = f"[{title}]({quote(names[index].replace(' ', '-'))})" if index else title
            out.append(f"{pad}- **{label}**" if depth == 0 else f"{pad}- {label}")
            walk(value, depth + 1)

    walk(nav, 0)
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "argseby/revoked"))
    parser.add_argument("--ref", default=os.environ.get("GITHUB_SHA", "main"))
    parser.add_argument("--strict", action="store_true", help="fail on any broken link or leftover syntax")
    args = parser.parse_args()

    if not (DOCS / "api" / "reference" / "index.md").exists():
        print("docs/api/reference is missing; run tools/docs/gen_api_reference.py first", file=sys.stderr)
        return 1

    nav = tomllib.loads((ROOT / "zensical.toml").read_text(encoding="utf-8"))["project"]["nav"]
    names, _ = assign_names(nav)
    conv = Converter(names, args.repo, args.ref)

    out: Path = args.out
    if out.exists():
        for child in out.iterdir():
            if child.name != ".git":
                shutil.rmtree(child) if child.is_dir() else child.unlink()
    out.mkdir(parents=True, exist_ok=True)

    for rel, name in names.items():
        file = f"{name.replace(' ', '-')}.md"
        text = conv.page(rel)
        conv.problems += leftovers(file, text)
        if (out / file).exists():
            conv.problems.append(f"{rel}: {file} is already another page")
        (out / file).write_text(text, encoding="utf-8")
    (out / "_Sidebar.md").write_text(sidebar(nav, names), encoding="utf-8")
    (out / "_Footer.md").write_text(
        f"Generated from [`docs/`](https://github.com/{args.repo}/tree/{args.ref}/docs) "
        "on every docs change to `main`. Changes made in the wiki are overwritten.\n",
        encoding="utf-8",
    )

    for problem in conv.problems:
        print(f"warning: {problem}", file=sys.stderr)
    print(f"{len(names)} pages written to {out}")
    return 1 if args.strict and conv.problems else 0


if __name__ == "__main__":
    sys.exit(main())
