"""Convert the assembled manuscript (Markdown) to LaTeX, with the figures embedded.

Run from the project folder:  python3 -I scripts/30_latex_manuscript.py [docs/manuscript/manuscript_v3.md]
Writes docs/manuscript/latex_vN/ (never overwrites): manuscript.tex, figures/*.png, and a zip of the
folder for Overleaf. pdflatex-compatible. Figures appear after the legends section, one per page
region, captioned with the legend text; the legend's [file] tag names the PNG in out/figures.
"""
import glob
import os
import re
import shutil
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else sorted(
    glob.glob("docs/manuscript/manuscript_v*.md"), key=lambda p: int(re.search(r"_v(\d+)", p).group(1)))[-1]
v = 1
while os.path.exists(f"docs/manuscript/latex_v{v}"):
    v += 1
OUT = f"docs/manuscript/latex_v{v}"
os.makedirs(f"{OUT}/figures")

UNI = {"°": r"\textdegree{}", "³": r"\textsuperscript{3}", "≥": r"$\geq$", "≤": r"$\leq$", "α": r"$\alpha$",
       "±": r"$\pm$", "–": "--", "—": "---", "×": r"$\times$", "−": "--", "’": "'", "‘": "`", "“": "``", "”": "''"}


def esc_text(s):
    s = s.replace("\\", r"\textbackslash{}")
    for c in "&%#_{}":
        s = s.replace(c, "\\" + c)
    s = s.replace("^", r"\^{}").replace("~", r"\textasciitilde{}")
    s = s.replace("<", r"$<$").replace(">", r"$>$")
    for k, r in UNI.items():
        s = s.replace(k, r)
    s = re.sub(r"\*\*(.+?)\*\*", r"\\textbf{\1}", s)
    s = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"\\emph{\1}", s)
    s = re.sub(r"(doi:)(10\.\S+?)(?=[\s,;]|\.?$)", lambda m: m.group(1) + r"\allowbreak " + m.group(2), s)
    return s


def inline(s):
    """Escape text but keep $...$ and $$...$$ math untouched."""
    parts = re.split(r"(\$\$.+?\$\$|\$[^$]+?\$)", s)
    out = []
    for p in parts:
        if p.startswith("$$"):
            out.append("\\[" + p[2:-2] + "\\]")
        elif p.startswith("$") and len(p) > 1:
            out.append(p)
        else:
            out.append(esc_text(p))
    return "".join(out)


def table(rows):
    cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows if not re.match(r"^\|[-|: ]+\|$", r.strip())]
    n = len(cells[0])
    first = 0.30 if n > 4 else 0.40
    rest = (1 - first) / (n - 1)
    spec = "".join(f">{{\\raggedright\\arraybackslash}}p{{{w:.3f}\\linewidth}}"
                   for w in [first] + [rest] * (n - 1))
    head = " & ".join(r"\textbf{" + inline(c) + "}" for c in cells[0]) + r" \\"
    body = "\n".join(" & ".join(inline(c) for c in (r + [""] * n)[:n]) + r" \\" for r in cells[1:])
    return ("{\\footnotesize\\setlength{\\tabcolsep}{3pt}\n\\begin{longtable}{" + spec + "}\n\\toprule\n" + head +
            "\n\\midrule\n\\endhead\n" + body + "\n\\bottomrule\n\\end{longtable}}\n")


lines = open(SRC, encoding="utf-8").read().split("\n")
title = lines[0].lstrip("# ").strip()
body, figs, i, section = [], [], 1, ""
while i < len(lines):
    ln = lines[i]
    if ln.startswith("## "):
        section = ln[3:].strip()
        if section == "References":
            body.append("\\section*{References}\n\\begin{enumerate}[label={\\arabic*.},leftmargin=2.2em,itemsep=1pt]\\small")
            i += 1
            while i < len(lines) and not lines[i].startswith("## "):
                m = re.match(r"^\d+\.\s+(.*)", lines[i])
                if m:
                    body.append("\\item " + inline(m.group(1)))
                i += 1
            body.append("\\end{enumerate}\n")
            continue
        body.append(("\\clearpage\n" if section in ("Tables", "Figure legends") else "") +
                    "\\section*{" + inline(section) + "}")
    elif ln.startswith("### "):
        body.append("\\subsection*{" + inline(ln[4:].strip()) + "}")
    elif ln.startswith("|"):
        rows = []
        while i < len(lines) and lines[i].startswith("|"):
            rows.append(lines[i])
            i += 1
        body.append(table(rows))
        continue
    elif ln.strip():
        m = re.search(r"\s*\[(fig[\w]+)\]\s*$", ln)
        if section == "Figure legends" and m:
            png = f"out/figures/{m.group(1)}.png"
            assert os.path.exists(png), png
            shutil.copy(png, f"{OUT}/figures/{m.group(1)}.png")
            leg = ln[:m.start()]
            body.append(inline(leg) + "\n")
            lab = re.match(r"\*\*(Fig\. \d+)\.\*\*\s*(.*)", leg)
            figs.append((m.group(1), lab.group(1), lab.group(2)))
        elif ln.startswith("$$"):
            body.append("\\[" + ln.strip()[2:-2] + "\\]")
        else:
            body.append(inline(ln) + "\n")
    i += 1

# front matter: lines between title and Abstract are author placeholders
fig_tex = ["\\clearpage\n\\section*{Figures}"]
for f, lab, cap in figs:
    fig_tex.append("\\begin{figure}[p]\n\\centering\n\\includegraphics[width=\\linewidth,height=0.78\\textheight,"
                   f"keepaspectratio]{{figures/{f}.png}}\n\\caption*{{\\textbf{{{lab}.}} {inline(cap)}}}\n\\end{{figure}}\n")

tex = r"""\documentclass[11pt,a4paper]{article}
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{lmodern,textcomp}
\usepackage[margin=2.5cm]{geometry}
\usepackage{amsmath,amssymb,bm}
\usepackage{graphicx,caption}
\usepackage{longtable,booktabs,array}
\usepackage{enumitem}
\usepackage[hidelinks]{hyperref}
\usepackage{setspace}
\onehalfspacing
\sloppy
\captionsetup{font=small,justification=raggedright,singlelinecheck=false}

\title{""" + inline(title) + r"""}
\author{[Authors]\\[2pt]\small [Affiliations]\\[2pt]\small Corresponding author: [name, email]}
\date{}

\begin{document}
\maketitle

"""
# drop the placeholder author lines already in the title block
start = next(k for k, b in enumerate(body) if b.startswith("\\section*{Abstract}"))
tex += "\n".join(body[start:]) + "\n" + "\n".join(fig_tex) + "\n\\end{document}\n"
open(f"{OUT}/manuscript.tex", "w", encoding="utf-8").write(tex)
shutil.make_archive(OUT, "zip", OUT)
print(f"from {SRC}\nwrote {OUT}/manuscript.tex, {len(figs)} figures, and {OUT}.zip")
