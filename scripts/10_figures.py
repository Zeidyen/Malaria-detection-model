"""Figures for the detection study (plain matplotlib).

Inputs are the outputs of scripts 02, 07, 08 and 09. Figures go to out/figures/. An existing
figure is never overwritten: a new version is saved as <name>_v2.png, _v3.png, ...

Run from the project folder:  python3 scripts/10_figures.py [MODEL]
MODEL is "arm" (monthly-updated AR1, default), "sat-all" (arm + satellite layers, the final
system from 2026-10-30) or "base" (yearly, linear trend).
"""
import json
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.collections import PolyCollection

MODEL = sys.argv[1] if len(sys.argv) > 1 else "arm"
OUT = "out/figures"
os.makedirs(OUT, exist_ok=True)


def save(fig, name):
    path = os.path.join(OUT, name + ".png")
    v = 2
    while os.path.exists(path):
        path = os.path.join(OUT, f"{name}_v{v}.png")
        v += 1
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)
    print("saved", path)


LABEL = {"outbreak": "transmission upsurge", "artefact": "reporting artefact"}   # wording, 2026-10-30
ZONE = {"Upper West": "North", "Upper East": "North", "North East": "North", "Northern": "North",
        "Savannah": "North", "Ashanti": "Forest", "Bono": "Forest", "Bono East": "Forest",
        "Ahafo": "Forest", "Eastern": "Forest", "Western North": "Forest", "Oti": "Forest",
        "Greater Accra": "Coast", "Central": "Coast", "Western": "Coast", "Volta": "Coast"}

cases = pd.read_csv("data/derived/cases_district_month.csv")
cases["date"] = pd.to_datetime(dict(year=cases.year, month=cases.m, day=1))
cases["zone"] = cases.Region.map(ZONE)
if MODEL == "base":
    pred = pd.concat([pd.read_csv(f"out/model_base_{y}_pred.csv") for y in range(2018, 2026)])
else:
    tag = "ar" if MODEL == "arm" else MODEL   # "sat-all": monthly AR1 + satellite layers
    pred = pd.concat([pd.read_csv(f"out/monthly/model_{tag}_{y}_{m:02d}_pred.csv")
                      for y in range(2018, 2026) for m in range(1, 13)])
pred["date"] = pd.to_datetime(dict(year=pred.year, month=pred.m, day=1))
alerts = pd.read_csv(f"out/alerts_{MODEL}_2018_2025.csv")
syn = pd.read_csv(f"out/synthetic_summary_{MODEL}.csv")
ev = pd.read_csv(f"out/synthetic_events_{MODEL}.csv")

# 1. National monthly confirmed cases by zone -------------------------------------------
fig, ax = plt.subplots(figsize=(9, 4))
z = cases.groupby(["date", "zone"]).conf_tot.sum().unstack() / 1000
for col in ["North", "Forest", "Coast"]:
    ax.plot(z.index, z[col], label=col)
ax.set_title("Monthly confirmed malaria cases by ecological zone, Ghana, 2015-2025")
ax.set_xlabel("Month")
ax.set_ylabel("Confirmed cases (thousands)")
ax.legend(title="Zone")
save(fig, "fig1_cases_by_zone")

# 2. Example districts: observed vs expected, with flags -----------------------------------
examples = ["Tema", "Krowor", "Ayawaso Central", "Kumasi", "Yunyoo-Nasuan", "Amansie West"]
fig, axes = plt.subplots(3, 2, figsize=(11, 9), sharex=True)
colors = {"transmission": "tab:red", "reporting": "tab:blue", "indeterminate": "tab:gray"}
CAUSE = {"transmission": "transmission", "reporting": "reporting", "indeterminate": "unclear"}
for ax, dname in zip(axes.flat, examples):
    p = pred[pred.District == dname].sort_values("date")
    h = cases[(cases.District == dname) & (cases.year < 2018)].sort_values("date")
    ax.plot(h.date, h.conf_tot, color="black", lw=0.8)
    ax.fill_between(p.date, p.lo95_adj, p.hi95_adj, color="tab:orange", alpha=0.3,
                    label="95% prediction interval (zone-adjusted)")
    ax.plot(p.date, p.pred_med_adj, color="tab:orange", lw=1, label="Expected (median)")
    ax.plot(p.date, p.conf_tot, color="black", lw=0.8, label="Observed")
    a = alerts[alerts.District == dname]
    for cls, c in colors.items():
        s = a[a.tier3 == cls]
        ax.scatter(pd.to_datetime(dict(year=s.year, month=s.m, day=1)), s.conf_tot, color=c,
                   s=18, zorder=3, label=f"Alert, likely cause: {CAUSE[cls]}")
    ax.set_title(dname)
    ax.set_ylabel("Confirmed cases")
seen = {}
for ax in axes.flat:
    for h_, l_ in zip(*ax.get_legend_handles_labels()):
        seen.setdefault(l_, h_)
fig.legend(seen.values(), seen.keys(), loc="lower center", ncol=3, frameon=False)
fig.suptitle("Observed and expected monthly confirmed cases, selected districts "
             "(each prediction fitted only on earlier data)")
fig.tight_layout(rect=(0, 0.07, 1, 0.97))
save(fig, "fig2_district_examples")

# 3. Flag rate by year, raw vs zone-adjusted ------------------------------------------------
fig, ax = plt.subplots(figsize=(7, 4))
r = pred.groupby("year")[["flag95", "flag95_adj"]].mean() * 100
w = 0.38
ax.bar(r.index - w / 2, r.flag95, w, label="Raw")
ax.bar(r.index + w / 2, r.flag95_adj, w, label="Zone-adjusted")
ax.axhline(5, color="black", ls="--", lw=1, label="Nominal 5%")
ax.set_title("Share of district-months flagged (above upper 95% limit), by year")
ax.set_xlabel("Predicted year")
ax.set_ylabel("District-months flagged (%)")
ax.set_xticks(r.index)
ax.legend()
save(fig, "fig3_flag_rate_by_year")

# 4. Synthetic events: sensitivity by event size -----------------------------------------
fig, axes = plt.subplots(1, 2, figsize=(10, 4), sharey=True)
for ax, typ in zip(axes, ["outbreak", "artefact"]):
    for L, ls in [(1, "-"), (3, "--")]:
        s = syn[(syn.type == typ) & (syn.L == L)].sort_values("k")
        ax.plot((s.k - 1) * 100, s.sensitivity * 100, marker="o", ls=ls, label=f"Detected, {L}-month event")
        ax.plot((s.k - 1) * 100, s.background * 100, marker="x", ls=ls, color="gray",
                label=f"Flagged without injection, {L}-month")
    ax.set_title(f"Injected {LABEL[typ]}s")
    ax.set_xlabel("Event size (% above observed)")
    ax.set_xticks([25, 50, 100])
axes[0].set_ylabel("Events with at least one flag (%)")
axes[0].legend(fontsize=8)
fig.suptitle("Detection of synthetic events, 2018-2025 (1,000 events per point)")
fig.tight_layout()
save(fig, "fig4_synthetic_sensitivity")

# 5. Likely-cause check (Tier 3 in the code): malaria share of visits vs change in positivity, synthetic events -----------
fig, ax = plt.subplots(figsize=(7, 5))
d = ev[ev.detected & (ev.k == 1.5)]
for typ, c in [("artefact", "tab:blue"), ("outbreak", "tab:red")]:
    s = d[d.type == typ]
    ax.scatter(s.pm_ratio, s.dtpr, s=6, alpha=0.4, color=c, label=f"Injected {LABEL[typ]} (+50%)")
ax.axvline(1.2, color="black", ls="--", lw=1, label="Thresholds (PM_T = 1.2, TPR_T = 0.02)")
ax.axhline(-0.02, color="black", ls="--", lw=1)
ax.set_xlim(0.4, 2.5)
ax.set_ylim(-0.4, 0.4)
ax.set_title("Likely-cause check: inputs for detected synthetic events")
ax.set_xlabel("Malaria share of OPD visits, ratio to same month in previous 3 years")
ax.set_ylabel("Change in test positivity vs previous 3 years")
ax.legend(fontsize=8, loc="lower right")
save(fig, "fig5_tier3_scatter")

# 6. Map: share of months flagged per district, 2018-2025 ---------------------------------
gj = json.load(open("data/derived/units_simplified.geojson"))
share = pred.groupby("unit").flag95_adj.mean() * 100
polys, vals = [], []
for f in gj["features"]:
    g = f["geometry"]
    rings = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
    for poly in rings:
        polys.append(np.array(poly[0]))
        vals.append(share.get(f["properties"]["unit"], np.nan))
fig, ax = plt.subplots(figsize=(6, 7.5))
pc = PolyCollection(polys, array=np.array(vals), cmap="viridis", edgecolor="white", linewidth=0.2)
ax.add_collection(pc)
ax.autoscale_view()
ax.set_aspect("equal")
ax.set_xlabel("Longitude")
ax.set_ylabel("Latitude")
ax.set_title("Share of months flagged per district, 2018-2025 (zone-adjusted)")
fig.colorbar(pc, ax=ax, label="Months flagged (%)", shrink=0.7)
save(fig, "fig6_map_flag_share")
