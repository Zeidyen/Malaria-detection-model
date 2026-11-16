"""One Word file with everything: the manuscript (with its figures under their legends), Additional
file 1 (supplementary notes S1-S9 with Figures S1-S10 embedded), and the one analysis figure used in
neither (fig4, sensitivity to simulated upsurges). Equations are rendered: inline math as text with
sub/superscripts, the model equation as an image.

Run from the project folder:  python3 -I scripts/31_word_complete.py [docs/manuscript/manuscript_vN.md]
Output: docs/manuscript/manuscript_complete_vN.docx (never overwrites)
"""
import glob
import os
import re
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from docx import Document
from docx.enum.section import WD_ORIENT  # noqa: F401
from docx.enum.text import WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt

D, FIG = "docs/manuscript", "out/figures"
vnum = lambda p: int(re.search(r"_v(\d+)\.", p).group(1))
MAIN = sys.argv[1] if len(sys.argv) > 1 else max(glob.glob(f"{D}/manuscript_v*.md"), key=vnum)
SUPP = f"{D}/supplement.md"
v = 1
while os.path.exists(f"{D}/manuscript_complete_v{v}.docx"):
    v += 1
OUT = f"{D}/manuscript_complete_v{v}.docx"
TMP = os.environ.get("TMPDIR", "/tmp")


def latest(name):
    c = glob.glob(f"{FIG}/{name}.png") + glob.glob(f"{FIG}/{name}_v*.png")
    return max(c, key=lambda p: vnum(p) if "_v" in os.path.basename(p) else 1)


# ---- math -------------------------------------------------------------------------------------
SYM = {r"\tilde{\mu}": "μ\u0303", r"\mu": "μ", r"\alpha": "α", r"\beta": "β", r"\sigma": "σ", r"\rho": "ρ",
       r"\phi": "φ", r"\Delta": "Δ", r"\geq": "≥", r"\leq": "≤", r"\log": "log", r"\dots": "…", r"\top": "ᵀ",
       r"\sum": "Σ", r"\times": "×"}


def math_runs(par, s):
    for k, r in SYM.items():
        s = s.replace(k, r)
    s = re.sub(r"\\(?:mathrm|mathbf|boldsymbol|text)\{([^{}]*)\}", r"\1", s)
    s = s.replace("<", " < ").replace(">", " > ").replace("=", " = ")
    s = re.sub(r" +", " ", s)
    i = 0
    while i < len(s):
        if s[i] in "_^" and i + 1 < len(s):
            if s[i + 1] == "{":
                depth, j = 1, i + 2
                while depth:
                    depth += {"{": 1, "}": -1}.get(s[j], 0)
                    j += 1
                txt, nxt = s[i + 2:j - 1].replace("{", "").replace("}", ""), j
            else:
                txt, nxt = s[i + 1], i + 2
            run = par.add_run(txt)
            run.font.subscript, run.font.superscript = s[i] == "_", s[i] == "^"
            i = nxt
        else:
            j = i
            while j < len(s) and s[j] not in "_^":
                j += 1
            par.add_run(s[i:j].replace("{", "").replace("}", ""))
            i = j


def equation_png(tex, k):
    tex = tex.replace(r"\boldsymbol", r"\mathbf")
    fig = plt.figure(figsize=(0.01, 0.01))
    fig.text(0, 0, f"${tex}$", fontsize=12)
    p = os.path.join(TMP, f"eq{k}.png")
    fig.savefig(p, dpi=300, bbox_inches="tight", pad_inches=0.05)
    plt.close(fig)
    return p


# ---- text -------------------------------------------------------------------------------------
def add_runs(par, text, bold=False):
    for part in re.split(r"(\$[^$]+\$|\*\*[^*]+\*\*|(?<![\w*])\*[^*\s][^*]*\*(?![\w*]))", text):
        if not part:
            continue
        if part.startswith("$"):
            math_runs(par, part[1:-1])
        elif part.startswith("**"):
            add_runs(par, part[2:-2], bold=True) if "$" in part else setattr(par.add_run(part[2:-2]), "bold", True)
        elif part.startswith("*") and len(part) > 2:
            par.add_run(part[1:-1]).italic = True
        else:
            par.add_run(part).bold = bold or None


def shade(cell, hex_):
    tc = cell._tc.get_or_add_tcPr()
    sh = OxmlElement("w:shd")
    sh.set(qn("w:val"), "clear"), sh.set(qn("w:color"), "auto"), sh.set(qn("w:fill"), hex_)
    tc.append(sh)


def add_table(doc, rows):
    n = max(len(r) for r in rows)
    t = doc.add_table(rows=len(rows), cols=n)
    t.style = "Table Grid"
    for r, row in enumerate(rows):
        for c in range(n):
            p = t.cell(r, c).paragraphs[0]
            add_runs(p, row[c] if c < len(row) else "")
            for run in p.runs:
                run.font.size = Pt(8.5)
                if r == 0:
                    run.bold = True
            if r == 0:
                shade(t.cell(r, c), "E7E6E6")
    doc.add_paragraph()


def add_figure(doc, name, caption):
    path = latest(name)
    doc.add_picture(path, width=Inches(6.3))
    p = doc.add_paragraph()
    add_runs(p, caption)
    for run in p.runs:
        run.font.size = Pt(9.5)
    return os.path.basename(path)


def blocks(text):
    """Group lines into blocks: headings, table rows, list items and paragraphs (hard wraps joined)."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    out, cur = [], None
    for ln in text.split("\n"):
        s = ln.rstrip()
        new = re.match(r"^(#{1,3} |\||- |\d+\. |\$\$)", s)
        if not s.strip() or s.strip() == "---":
            cur = None
            continue
        if s.startswith("|"):
            if out and out[-1][0] == "table":
                out[-1][1].append(s)
            else:
                out.append(["table", [s]])
            cur = None
        elif new:
            cur = ["head" if s.startswith("#") else "eq" if s.startswith("$$") else
                   "bullet" if s.startswith("- ") else "num" if re.match(r"^\d+\. ", s) else "par", s]
            out.append(cur)
        elif cur is not None and cur[0] != "head":
            cur[1] += " " + s.strip()
        else:
            cur = ["par", s.strip()]
            out.append(cur)
    return out


used = []


def render(doc, text, supplement=False):
    section, eqk = "", 0
    for kind, val in blocks(text):
        if kind == "head":
            lev = len(val.split(" ")[0])
            title = val[lev + 1:].strip()
            section = title
            if title in ("Tables", "Figure legends") and not supplement:
                doc.add_page_break()
            doc.add_heading(title, level=0 if lev == 1 else lev - 1)
        elif kind == "table":
            rows = [[c.strip() for c in r.strip().strip("|").split("|")] for r in val
                    if not re.match(r"^\|[-|: ]+\|$", r.strip())]
            if supplement and section == "Supplementary figures":
                add_table(doc, rows)
                for num, content, name in rows[1:]:
                    used.append(add_figure(doc, name, f"**Figure {num}.** {content}."))
            else:
                add_table(doc, rows)
        elif kind == "eq":
            eqk += 1
            doc.add_picture(equation_png(val.strip().strip("$"), eqk), width=Inches(6.3))
        elif kind == "bullet":
            add_runs(doc.add_paragraph(style="List Bullet"), val[2:])
        else:
            m = re.search(r"\s*\[(fig\w+)\]\s*$", val)
            if m and section == "Figure legends":
                used.append(add_figure(doc, m.group(1), val[:m.start()]))
            else:
                add_runs(doc.add_paragraph(), val)


doc = Document()
st = doc.styles["Normal"]
st.font.name, st.font.size = "Times New Roman", Pt(11)
st.element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")
for s in doc.sections:
    s.left_margin = s.right_margin = Inches(1)

render(doc, open(MAIN, encoding="utf-8").read())
doc.add_page_break()
render(doc, open(SUPP, encoding="utf-8").read(), supplement=True)
doc.add_page_break()
doc.add_heading("Additional analysis figure (not cited in the manuscript)", level=1)
used.append(add_figure(doc, "fig4_synthetic_sensitivity",
                       "**Figure A1.** Detection of simulated events at the default 95% limit, 2018-2025 (1,000 events per "
                       "point): transmission upsurges (left) and reporting artefacts (right), one- and three-month "
                       "events, with the share of the same district-months flagged without an injected event."))
doc.save(OUT)
print(f"from {MAIN} + {SUPP}\nsaved {OUT}\n{len(used)} figures: {', '.join(used)}")
