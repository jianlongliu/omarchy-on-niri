#!/usr/bin/env python3
"""守住 docs/ 各卷之间的互引不失效。

用法:
    scripts/check-doc-refs.py [docdir] [--quiet]

默认扫描 <repo>/docs/*.md，也可传一个目录参数覆盖（便于自测）。
逐条打印失效引用，末尾一行统计；失效 K>0 时退出码 1，K=0 时退出码 0。

检查口径
--------
每卷先建「已定义的号」索引：
  * 标题行：`## 8. xxx` → 8、`### §11.28 xxx` → 11.28、`## 0.1 xxx` → 0.1；
  * 粗体小标题：`**8.9.3 xxx**` → 8.9.3；
  * 「本卷目录」里的条目：`- 33. xxx` / `- 8.8 xxx` / `- §11.22 xxx` → 33 / 8.8 / 11.22
    （visual.md 的 §33 只在目录里出现，不看目录就会误报）。

会校验的引用：
  * 文件：`docs/<name>.md`（含 markdown 链接目标）和 `` `<name>.md` `` 这类不带目录的
    简写（按 docs/ 解析，只认「确实是卷」的名字）—— 目标必须存在。
  * 章节 `§8` / `§8.11` / `§11.28`（号只取数字和点；`§8 第 13 条` 里的 13 不当号）。
    - 紧邻写法 `` `lock.md` §11.28 `` / `docs/lock.md §11.28`：只认点名的那个卷，
      该卷没定义这个号就报错 —— 这是最容易烂掉的一类引用。
    - `` `docs/shims.md` §8 第 22 条 ``：§8 这本总账在主文档里，第 22 条落在 shims.md，
      所以额外认「条号」：点名卷定义了 22（含目录条目）也算过。
    - 本行没点名卷的裸 `§N`：按本仓库「编号全局唯一、永不改号」的约定在全部卷里找 ——
      拆卷后 §8.7 在 upstream.md、§8.18 在 lock.md、§8 本体在 omarchy-on-niri-port.md，
      正文里到处是没点名的 `§8.7`；若一律按「本卷」校验会报出一大片并非真错的引用。

不算引用、不校验的：
  * 指向别的目录或仓库外的路径（`../agents/skills/x.md`、`split-greeter/README.md`、
    `~/Documents/x.md`、`/var/tmp/x.md`、`https://…/docs/x.md`）；
  * 裸文件名但不是卷的（`README.md`、`AGENTS.md`、`omarchy-niri-migration.md`…）。

有意与需求不同的一处：**没有**把「卷内出现过的 §N」并进索引。试验过，那会让
local-overrides.md 因为提到过 §11.28 就"定义"了 11.28，反而把 `local-overrides.md §11.28`
这种真错引用放过。索引只由定义构成。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SEC_NUM = r"\d+(?:\.\d+)*"
REF_NUM = SEC_NUM + r"[a-z]?"
SEC = re.compile(r"§\s?(" + SEC_NUM + r")")
FILE = re.compile(r"(?P<path>(?:[A-Za-z0-9._~-]+/)*)(?P<file>[A-Za-z0-9_.-]+\.md)")

# 点名卷与 § 之间的分隔符：只允许空白/引号/反引号/括号/顿号逗号冒号等标点，
# 不允许中日韩文字 —— 否则会把老远一个文件名错认成这个 § 的宿主。
_W = r"[\s`'\"()\[\]{}<>（）【】「」『』、,，:：;；=~*]+"
SEC_PAIR = re.compile(
    r"(?P<path>(?:docs/)?(?:[A-Za-z0-9._-]+/)?)(?P<file>[A-Za-z0-9_.-]+\.md)"
    + _W
    + r"§\s?("
    + SEC_NUM
    + r")(?P<rest>[^\n]{0,4}?第\s*(?P<item>"
    + REF_NUM
    + r")\s*条)?"
)

HEAD_DEF = re.compile(r"^#{1,6}\s+§?\s*(" + REF_NUM + r")(?=[.\s、:：)）]|$)")
BOLD_DEF = re.compile(r"^\s*\*\*\s*§?\s*(" + REF_NUM + r")(?=[.\s、:：)）]|$)")
TOC_ITEM = re.compile(r"^\s*[-*]\s+§?\s*(" + REF_NUM + r")(?=[.\s、:：)）]|$)")
TOC_HEAD = re.compile(r"^#{1,6}\s+本卷目录\s*$")
ANY_HEAD = re.compile(r"^#{1,6}\s")


class Volume:
    def __init__(self, path: Path, display: str) -> None:
        self.path = path
        self.display = display
        self.name = path.name
        self.defined: set[str] = set()
        self.lines: list[str] = []


def load(path: Path, display: str) -> Volume:
    vol = Volume(path, display)
    vol.lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    in_toc = False
    for line in vol.lines:
        if ANY_HEAD.match(line):
            in_toc = bool(TOC_HEAD.match(line))
            if m := HEAD_DEF.match(line):
                vol.defined.add(m.group(1))
        else:
            if m := BOLD_DEF.match(line):
                vol.defined.add(m.group(1))
            if in_toc and (m := TOC_ITEM.match(line)):
                vol.defined.add(m.group(1))
    return vol


def scan(vol: Volume, docdir: Path, defined: dict[str, set[str]],
         candidates: set[str], known: set[str]) -> tuple[list[str], int, int]:
    problems: list[str] = []
    n_sec = n_file = 0

    def add(msg: str) -> None:
        problems.append(f"{vol.display}:{lineno}: {msg}")

    for lineno, raw in enumerate(vol.lines, 1):
        consumed: list[tuple[int, int]] = []

        # 1. 「点名卷 + §号」的紧邻对（最容易烂掉的一类）
        for m in SEC_PAIR.finditer(raw):
            path, name, num, item = (
                m.group("path"),
                m.group("file"),
                m.group(3),
                m.group("item"),
            )
            consumed.append((m.start("file") - len(path), m.end()))
            if path and path != "docs/":
                continue  # ../agents/…、split-greeter/… 之类不归本工具管
            n_sec += 1
            shown = f"{path}{name} §{num}" + (f" 第 {item} 条" if item else "")
            if not (docdir / name).is_file():
                add(f"引用 {shown} —— 文件不存在")
                continue
            if name not in defined:
                continue  # 扫到的不是卷（本次 docdir 里没有这个 .md）
            owned = defined[name]
            if num in owned or (item and item in owned):
                continue
            if item:
                add(f"引用 {shown} —— 目标卷没有 §{num}，也没有第 {item} 条")
            else:
                add(f"引用 {shown} —— 目标卷没有这个号")

        # 2. 本行没点名卷的裸 §号：按全局唯一编号在全部卷里找
        for m in SEC.finditer(raw):
            if any(s <= m.start() and m.end() <= e for s, e in consumed):
                continue
            n_sec += 1
            num = m.group(1)
            if num not in vol.defined and num not in known:
                add(f"引用 §{num}（本行未点名卷） —— 全库没有这个号")

        # 3. 文件引用
        for m in FILE.finditer(raw):
            path, name = m.group("path"), m.group("file")
            if any(s <= m.start() and m.end() <= e for s, e in consumed):
                continue  # 已作为 § 的宿主登记过
            if path == "docs/":
                pass
            elif path or name not in candidates:
                continue  # 别的目录；或裸名但不是卷（README.md / AGENTS.md / …）
            n_file += 1
            if not (docdir / name).is_file():
                add(f"引用 {path}{name} —— 文件不存在")
    return problems, n_sec, n_file


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="校验 docs/ 卷间互引（文件引用 + §号引用）")
    ap.add_argument("docdir", nargs="?", default="docs", help="文档目录（默认 docs/）")
    ap.add_argument("-q", "--quiet", action="store_true", help="只打印统计")
    args = ap.parse_args(argv)

    docdir = Path(args.docdir).resolve()
    if not docdir.is_dir():
        print(f"check-doc-refs: 目录不存在: {docdir}", file=sys.stderr)
        return 2

    volumes = [
        load(p, str(Path(args.docdir) / p.name))
        for p in sorted(docdir.glob("*.md"))
        if p.is_file()
    ]
    defined = {v.name: v.defined for v in volumes}
    known = set().union(*defined.values()) if defined else set()

    # 候选卷名：目录里的卷 + `docs/x.md` 点名过的 + 「x.md §N」点名过的
    candidates = set(defined)
    for v in volumes:
        for line in v.lines:
            for m in SEC_PAIR.finditer(line):
                if m.group("path") in ("", "docs/"):
                    candidates.add(m.group("file"))
            for m in FILE.finditer(line):
                if m.group("path") == "docs/":
                    candidates.add(m.group("file"))

    total_sec = total_file = 0
    problems: list[str] = []
    for v in volumes:
        probs, ns, nf = scan(v, docdir, defined, candidates, known)
        problems += probs
        total_sec += ns
        total_file += nf

    if not args.quiet:
        for line in problems:
            print(line)
    print(f"检查 {len(volumes)} 卷、{total_sec + total_file} 条引用，失效 {len(problems)} 条")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
