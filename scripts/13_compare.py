"""Head-to-head on the same synthetic outbreaks: our model vs Farrington flexible vs consensus detector.

Usage (project folder):  python3 -I scripts/13_compare.py [MODEL=arm]   (sat-all: final system, arm shown too)
Inputs: out/synthetic_summary_<MODEL>.csv (09), out/synthetic_farrington.csv (11),
        out/synthetic_consensus.csv (12). All three were scored on the injections in
        out/synthetic_injections_<MODEL>.csv.
Output: out/comparison_outbreaks.csv and out/figures/fig7_comparison (never overwritten).
Sensitivity always comes with the false-alert rate of the same setting: a method is only better
if it detects more at the same or a lower false-alert rate.
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

MODEL = sys.argv[1] if len(sys.argv) > 1 else "arm"
ours = pd.read_csv(f"out/synthetic_summary_{MODEL}.csv").assign(method="this model", setting="95% limit, zone-adjusted")
if MODEL != "arm":   # also show the model without satellite layers, as a reference point
    ours = pd.concat([ours.assign(setting="95% limit, zone-adjusted, " + MODEL),
                      pd.read_csv("out/synthetic_summary_arm.csv").assign(method="this model", setting="95% limit, zone-adjusted, no satellite")])
far = pd.read_csv("out/synthetic_farrington.csv")
far["setting"] = "alpha " + far.alpha.map(lambda a: f"{a:g}")
con = pd.read_csv("out/synthetic_consensus.csv")
con["setting"] = "q " + con.q.map(lambda a: f"{a:g}") + ", S>=" + con.S.astype(str)

# settings shown in the table: published defaults, and the lowest-false-alert settings near ours
keep = pd.concat([
    ours,
    far[far.alpha.isin([0.05, 0.0001])],
    con[((con.q == 0.10) & (con.S == 3)) | ((con.q == 0.02) & (con.S == 3))],
])
keep["label"] = keep.method + " (" + keep.setting + ")"
tab = (keep[keep.type == "outbreak"]
       .assign(cell=lambda d: "+" + ((d.k - 1) * 100).round().astype(int).astype(str) + "%, " + d.L.astype(int).astype(str) + " mo")
       .pivot_table(index="label", columns="cell", values="sensitivity"))
fa = keep[keep.type == "outbreak"].groupby("label").false_alert_rate.mean()
tab.insert(0, "false_alert_rate", fa)
tab = tab.sort_values("false_alert_rate")
tab.round(3).to_csv("out/comparison_outbreaks.csv")
print(tab.round(3).to_string())

# figure: sensitivity vs false-alert rate, one panel per outbreak size and duration
fig, axes = plt.subplots(2, 3, figsize=(12, 7), sharex=True, sharey=True)
for i, L in enumerate([1, 3]):
    for j, k in enumerate([1.25, 1.5, 2.0]):
        ax = axes[i, j]
        sel = lambda d: d[(d.type == "outbreak") & (d.k == k) & (d.L == L)]
        f = sel(far).sort_values("false_alert_rate")
        ax.plot(f.false_alert_rate * 100, f.sensitivity * 100, marker="o", ms=3, label="Farrington flexible (alpha varied)")
        for S, ls in [(3, "-"), (4, "--"), (2, ":")]:
            c = sel(con)[sel(con).S == S].sort_values("false_alert_rate")
            ax.plot(c.false_alert_rate * 100, c.sensitivity * 100, marker="s", ms=3, ls=ls, color="tab:green",
                    label=f"Consensus detector, S >= {S} (q varied)")
        for (st, o), (col, mk) in zip(sel(ours).groupby("setting", sort=False), [("tab:red", "o"), ("black", "x")]):
            lab = "This model" if MODEL == "arm" else ("This model, no satellite" if "no satellite" in st else "This model + satellite")
            ax.scatter(o.false_alert_rate * 100, o.sensitivity * 100, color=col, marker=mk, zorder=4, s=40, label=lab)
        ax.set_xscale("log")
        ax.set_title(f"+{int(round((k - 1) * 100))}% for {L} month{'s' if L > 1 else ''}")
        if j == 0:
            ax.set_ylabel("Upsurges detected (%)")
handles, labels = axes[0, 0].get_legend_handles_labels()
fig.legend(handles, labels, loc="lower center", ncol=3, frameon=False)
fig.supxlabel("False-alert rate (% of district-months without an event, log scale)", y=0.07)
fig.suptitle("Detection of the same injected malaria upsurges, 2018-2025, by method")
fig.tight_layout(rect=(0, 0.1, 1, 0.96))

os.makedirs("out/figures", exist_ok=True)
path, v = "out/figures/fig7_comparison.png", 2
while os.path.exists(path):
    path, v = f"out/figures/fig7_comparison_v{v}.png", v + 1
fig.savefig(path, dpi=200, bbox_inches="tight")
print("saved", path)
