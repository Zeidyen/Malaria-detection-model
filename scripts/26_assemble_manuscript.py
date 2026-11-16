"""Assemble the manuscript: number citations in order of first appearance (Vancouver), append the
reference list, and write Markdown and Word versions. Never overwrites: a new version gets _v2, ...

Run from the project folder:  python3 -I scripts/26_assemble_manuscript.py
Input : docs/manuscript/manuscript_source.md  (citations as [Key] or [Key; Key], keys as in references.md)
        docs/manuscript/references.md          (lines "- **Key [CHECK].** text")
Output: docs/manuscript/manuscript_vN.md and .docx
"""
import os
import re
import sys

from docx import Document
from docx.shared import Pt

D = "docs/manuscript"
src = open(os.path.join(D, "manuscript_source.md")).read()

refs, check = {}, set()
for line in open(os.path.join(D, "references.md")):
    m = re.match(r"- \*\*(.+?)(?: \[CHECK\])?\.\*\* (.+)", line.strip())
    if m:
        refs[m.group(1)] = m.group(2)
        if "[CHECK]" in line.split("**")[1]:
            check.add(m.group(1))

order, missing = [], set()
CITE = re.compile(r"\[([A-Z][^\]]*?\d{4}[^\]]*?)\]")


def number(match):
    keys = [k.strip() for k in match.group(1).split(";")]
    if not all(k in refs for k in keys):
        missing.update(k for k in keys if k not in refs)
        return match.group(0)
    nums = []
    for k in keys:
        if k not in order:
            order.append(k)
        nums.append(order.index(k) + 1)
    nums = sorted(set(nums))
    parts, i = [], 0               # compress runs: 3,4,5 -> 3-5
    while i < len(nums):
        j = i
        while j + 1 < len(nums) and nums[j + 1] == nums[j] + 1:
            j += 1
        parts.append(f"{nums[i]}-{nums[j]}" if j - i >= 2 else ", ".join(map(str, nums[i:j + 1])))
        i = j + 1
    return "[" + ", ".join(parts) + "]"


# number the body only (up to the Abbreviations), so legends/tables do not reorder references
cut = src.index("## Abbreviations")
body = CITE.sub(number, src[:cut]) + CITE.sub(number, src[cut:])
if missing:
    sys.exit(f"Citation keys not in references.md: {sorted(missing)}")
reflist = "\n".join(f"{i + 1}. {refs[k]}" for i, k in enumerate(order))
tail = body.index("## Tables")
out = body[:tail] + "## References\n\n" + reflist + "\n\n" + body[tail:]
unused = sorted(set(refs) - set(order))

v, path = 1, os.path.join(D, "manuscript_v1.md")
while os.path.exists(path):
    v += 1
    path = os.path.join(D, f"manuscript_v{v}.md")
open(path, "w").write(out)
print("saved", path, f"| {len(order)} references cited | to verify: {sorted(set(order) & check)}")
if unused:
    print("in references.md but not cited:", unused)

# ---- Word version (plain: headings, paragraphs with bold/italic, tables; equations stay as text) ----
doc = Document()
st = doc.styles["Normal"]
st.font.name = "Times New Roman"
st.font.size = Pt(11)


def add_runs(par, text):
    for part in re.split(r"(\*\*[^*]+\*\*|\*[^*]+\*)", text):
        if part.startswith("**") and part.endswith("**"):
            par.add_run(part[2:-2]).bold = True
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            par.add_run(part[1:-1]).italic = True
        elif part:
            par.add_run(part)


lines = out.split("\n")
i = 0
while i < len(lines):
    ln = lines[i]
    if ln.startswith("|"):
        rows = []
        while i < len(lines) and lines[i].startswith("|"):
            if not re.match(r"^\|[-| ]+\|$", lines[i]):
                rows.append([c.strip() for c in lines[i].strip("|").split("|")])
            i += 1
        t = doc.add_table(rows=len(rows), cols=len(rows[0]))
        t.style = "Table Grid"
        for r, row in enumerate(rows):
            for c, cell in enumerate(row):
                add_runs(t.cell(r, c).paragraphs[0], cell)
                if r == 0:
                    for run in t.cell(r, c).paragraphs[0].runs:
                        run.bold = True
        continue
    m = re.match(r"^(#{1,3}) (.*)", ln)
    if m:
        doc.add_heading(m.group(2), level=len(m.group(1)) - 1 if len(m.group(1)) > 1 else 0)
    elif re.match(r"^\d+\. ", ln) and "## References" in out[:out.find(ln)]:
        add_runs(doc.add_paragraph(), ln)
    elif ln.strip():
        add_runs(doc.add_paragraph(), ln.replace("$$", ""))
    i += 1
dpath = path[:-3] + ".docx"
doc.save(dpath)
print("saved", dpath)
