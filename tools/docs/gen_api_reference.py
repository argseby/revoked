#!/usr/bin/env python3
"""Render docs/api/openapi.yaml into Markdown pages under docs/api/reference/.

The docs site builds with zensical, which runs a fixed set of plugins and no
arbitrary MkDocs ones — so the usual OpenAPI renderers are unavailable and the
spec is turned into pages here instead, before the build.

Output is generated: it is gitignored and rebuilt in CI, the same arrangement
the Flutter client uses for its MobX code.
"""

import re
import shutil
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "docs" / "api" / "openapi.yaml"
OUT = ROOT / "docs" / "api" / "reference"

METHODS = ("get", "post", "patch", "put", "delete", "head", "options")


def slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def resolve(spec: dict, node):
    """Follow a local $ref one level. The spec only uses local refs."""
    if isinstance(node, dict) and "$ref" in node:
        target = spec
        for part in node["$ref"].lstrip("#/").split("/"):
            target = target[part]
        return target
    return node


def type_of(schema: dict, link: bool = True) -> str:
    if not isinstance(schema, dict):
        return ""
    if "$ref" in schema:
        name = schema["$ref"].rsplit("/", 1)[-1]
        return f"[{name}](schemas.md#{slugify(name)})" if link else name
    if "allOf" in schema:
        return type_of(schema["allOf"][0], link)
    base = schema.get("type", "")
    if base == "array":
        inner = type_of(schema.get("items", {}), link)
        return f"array of {inner}" if inner else "array"
    if "enum" in schema:
        return f"{base} (`" + "` \\| `".join(str(v) for v in schema["enum"]) + "`)"
    return base


def render_properties(spec: dict, schema: dict, lines: list, indent: str = "") -> None:
    schema = resolve(spec, schema)
    props = schema.get("properties") if isinstance(schema, dict) else None
    if not props:
        return
    lines.append(f"{indent}| Field | Type | Notes |")
    lines.append(f"{indent}|---|---|---|")
    for name, prop in props.items():
        desc = " ".join((prop.get("description") or "").split())
        lines.append(f"{indent}| `{name}` | {type_of(prop)} | {desc} |")
    lines.append("")


def render_operation(spec: dict, path: str, method: str, op: dict,
                     shared_params: list, lines: list) -> None:
    lines.append(f"### `{method.upper()} {path}`")
    lines.append("")
    if op.get("summary"):
        lines.append(f"**{op['summary']}**")
        lines.append("")

    security = op.get("security", spec.get("security", []))
    if security == []:
        lines.append("!!! info \"Unauthenticated\"")
        lines.append("    Callable with no credential.")
        lines.append("")
    else:
        names = sorted({k for entry in security for k in entry})
        lines.append(f"Auth: {', '.join('`' + n + '`' for n in names)}")
        lines.append("")

    if op.get("description"):
        lines.append(op["description"].rstrip())
        lines.append("")

    params = [resolve(spec, p) for p in (shared_params + op.get("parameters", []))]
    if params:
        lines.append("**Parameters**")
        lines.append("")
        lines.append("| Name | In | Required | Notes |")
        lines.append("|---|---|---|---|")
        for p in params:
            required = "yes" if p.get("required") else "no"
            desc = " ".join((p.get("description") or "").split())
            lines.append(f"| `{p['name']}` | {p.get('in','')} | {required} | {desc} |")
        lines.append("")

    body = op.get("requestBody")
    if body:
        lines.append("**Request body**")
        lines.append("")
        if body.get("description"):
            lines.append(body["description"].rstrip())
            lines.append("")
        for media, spec_media in body.get("content", {}).items():
            lines.append(f"`{media}`")
            lines.append("")
            render_properties(spec, spec_media.get("schema", {}), lines)

    lines.append("**Responses**")
    lines.append("")
    lines.append("| Status | Meaning |")
    lines.append("|---|---|")
    for code, resp in op.get("responses", {}).items():
        resolved = resolve(spec, resp)
        desc = " ".join((resolved.get("description") or "").split())
        lines.append(f"| `{code}` | {desc} |")
    lines.append("")

    ok = op.get("responses", {}).get("200")
    if ok:
        schema = resolve(spec, ok).get("content", {}).get("application/json", {}).get("schema")
        if schema:
            resolved = resolve(spec, schema)
            if isinstance(resolved, dict) and resolved.get("properties"):
                lines.append("**Response fields**")
                lines.append("")
                render_properties(spec, resolved, lines)


def main() -> int:
    if not SPEC.exists():
        print(f"spec not found: {SPEC}", file=sys.stderr)
        return 1
    spec = yaml.safe_load(SPEC.read_text())

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    groups: dict[str, list[tuple[str, str, dict, list]]] = {}
    for path, item in spec["paths"].items():
        shared = item.get("parameters", [])
        for method in METHODS:
            op = item.get(method)
            if not op:
                continue
            for tag in op.get("tags", ["Other"]):
                groups.setdefault(tag, []).append((path, method, op, shared))

    order = [t["name"] for t in spec.get("tags", [])]
    described = {t["name"]: t.get("description", "") for t in spec.get("tags", [])}
    ordered = [t for t in order if t in groups] + [t for t in groups if t not in order]

    for tag in ordered:
        lines = [f"# {tag}", ""]
        if described.get(tag):
            lines.append(described[tag].rstrip())
            lines.append("")
        for path, method, op, shared in groups[tag]:
            render_operation(spec, path, method, op, shared, lines)
        (OUT / f"{slugify(tag)}.md").write_text("\n".join(lines).rstrip() + "\n")

    schema_lines = [
        "# Schemas",
        "",
        "Shapes shared across more than one endpoint.",
        "",
    ]
    for name, schema in sorted(spec.get("components", {}).get("schemas", {}).items()):
        schema_lines.append(f"## {name}")
        schema_lines.append("")
        if schema.get("description"):
            schema_lines.append(schema["description"].rstrip())
            schema_lines.append("")
        render_properties(spec, schema, schema_lines)
    (OUT / "schemas.md").write_text("\n".join(schema_lines).rstrip() + "\n")

    index = [
        "# API reference",
        "",
        "Generated from `openapi.yaml`. For the concepts behind these endpoints —",
        "how grants stay live, how the trust chain is walked, what a callback",
        "delivers — start with the guides alongside this section.",
        "",
        "| Group | Covers |",
        "|---|---|",
    ]
    for tag in ordered:
        summary = " ".join(described.get(tag, "").split())
        if len(summary) > 140:
            summary = summary[:137].rsplit(" ", 1)[0] + "…"
        index.append(f"| [{tag}]({slugify(tag)}.md) | {summary} |")
    index.append("| [Schemas](schemas.md) | Shapes shared across more than one endpoint. |")
    index += [
        "",
        "## Machine-readable spec",
        "",
        "The [OpenAPI document](../openapi.yaml) is the source these pages are",
        "generated from. Point a client generator or an HTTP client at it",
        "directly rather than transcribing from here.",
        "",
    ]
    (OUT / "index.md").write_text("\n".join(index))

    total = sum(len(v) for v in groups.values())
    print(f"wrote {len(ordered)} pages covering {total} operations to {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
