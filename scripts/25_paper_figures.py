"""Four figures for the paper that the earlier scripts do not draw (plain matplotlib).

Run from the project folder:  python3 -I scripts/25_paper_figures.py
  fig16_satellite_gain_ci    gain in sensitivity at a fixed 2% false-alert rate over the reference
                             model (arm), with paired district bootstrap 95% intervals (20_bootstrap.R)
  fig17_skill_by_year        CRPS and 95% coverage by year: linear-trend baseline, reference (arm),
                             final system (sat-all) (07, 17_satellite_value.R; zone-adjusted)
  fig18_cluster_size         sensitivity at 2% false alerts by number of neighbouring districts
                             affected, zone-adjusted vs raw vs either (23_clustered.R)
  fig19_real_events          observed / expected in each documented event-district, flagged or not
                             (21_real_events.R)
Figures are never overwritten: a new version gets _v2, _v3, ...
"""
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

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


CELLS = ["+25%_1mo", "+25%_3mo", "+50%_1mo", "+50%_3mo", "+100%_1mo", "+100%_3mo"]
CELL_LAB = {"+25%_1mo": "+25%, 1 month", "+25%_3mo": "+25%, 3 months", "+50%_1mo": "+50%, 1 month",
            "+50%_3mo": "+50%, 3 months", "+100%_1mo": "doubling, 1 month", "+100%_3mo": "doubling, 3 months"}

# 16. Satellite gain with bootstrap intervals -----------------------------------------------
MODELS = [("sat-all", "All layers (final system)"), ("sat-all-l13", "All layers, lags 1-3 only"),
          ("sat-era5", "+ temperature, humidity (ERA5)"), ("sat-ndvi", "+ NDVI (MODIS)"),
          ("sat-lst", "+ land surface temp. (MODIS)"), ("sat-rain", "+ rainfall (CHIRPS)"),
          ("sat-env", "+ land cover, night lights"), ("sat-sm", "+ soil moisture (SMAP)")]
bs = {m: pd.read_csv(f"out/bootstrap_arm_vs_{m}.csv").set_index("cell") for m, _ in MODELS}
fig, axes = plt.subplots(1, 6, figsize=(16, 4.6), sharey=True)
y = np.arange(len(MODELS))[::-1]
for ax, cell in zip(axes, CELLS):
    for yi, (m, _) in zip(y, MODELS):
        r = bs[m].loc[cell]
        c = "tab:red" if m.startswith("sat-all") else "tab:blue"
        ax.errorbar(100 * r.gain, yi, xerr=[[100 * (r.gain - r.gain_lo)], [100 * (r.gain_hi - r.gain)]],
                    fmt="o", color=c, capsize=3, ms=5)
    ax.axvline(0, color="gray", lw=1, ls="--")
    ax.set_title(CELL_LAB[cell])
    ax.set_xlabel("Gain (percentage points)")
axes[0].set_yticks(y)
axes[0].set_yticklabels([lab for _, lab in MODELS])
fig.suptitle("Gain in upsurges detected at a fixed 2% false-alert rate over the model without satellite "
             "or climate data, with 95% district bootstrap intervals")
fig.tight_layout()
save(fig, "fig16_satellite_gain_ci")

# 17. Skill by year ---------------------------------------------------------------------------
by = pd.read_csv("out/satellite_value_by_year.csv")
base = pd.concat([pd.read_csv(f"out/model_base_{yy}_pred.csv") for yy in range(2018, 2026)])
base_y = base.groupby("year").apply(lambda x: pd.Series({
    "crps": x.crps_adj.mean(),
    "coverage": ((x.conf_tot >= x.lo95_adj) & (x.conf_tot <= x.hi95_adj)).mean()})).reset_index()
fig, axes = plt.subplots(1, 2, figsize=(12, 4.2))
series = [(base_y, "Linear-trend baseline (yearly refit)", "tab:gray"),
          (by[by.model == "arm"], "Reference: monthly AR1, no satellite", "tab:blue"),
          (by[by.model == "sat-all"], "Final system: + satellite and climate", "tab:red")]
for d, lab, c in series:
    axes[0].plot(d.year, d.crps, marker="o", color=c, label=lab)
    axes[1].plot(d.year, d.coverage, marker="o", color=c, label=lab)
axes[0].set_ylabel("Mean CRPS (cases; lower is better)")
axes[0].set_title("Prediction error")
axes[1].axhline(0.95, color="black", ls="--", lw=1, label="Nominal 95%")
axes[1].set_ylabel("Share of observations inside the 95% interval")
axes[1].set_title("Coverage of the 95% prediction interval")
for ax in axes:
    ax.set_xlabel("Year")
axes[0].set_ylim(bottom=0)
axes[1].legend(fontsize=8, loc="lower right")
axes[0].legend(fontsize=8, loc="lower left")
fig.suptitle("Out-of-sample prediction skill by year, 2018-2025 (zone-adjusted)")
fig.tight_layout()
save(fig, "fig17_skill_by_year")

# 18. Cluster size ----------------------------------------------------------------------------
cl = pd.read_csv("out/clustered_sat-all.csv")
RULES = [("zone-adjusted", "Zone-adjusted (the system)", "tab:red"), ("raw", "No zone adjustment", "tab:blue"),
         ("either", "Either (max of the two)", "tab:green")]
fig, axes = plt.subplots(1, 4, figsize=(15, 4), sharey=True)
for ax, (k, L) in zip(axes, [(1.5, 1), (1.5, 3), (2, 1), (2, 3)]):
    for rule, lab, c in RULES:
        d = cl[(cl.k == k) & (cl.L == L) & (cl.rule == rule)].sort_values("size")
        ax.plot(d["size"], 100 * d.sens_district_at2, marker="o", color=c, label=lab)
    ax.set_xscale("log")
    ax.set_xticks([1, 3, 5, 10, 20])
    ax.set_xticklabels(["1", "3", "5", "10", "20"])
    ax.set_title(f"{'+50%' if k == 1.5 else 'doubling'}, {L} month{'s' if L > 1 else ''}")
    ax.set_xlabel("Neighbouring districts affected")
    ax.set_ylim(0, 100)
axes[0].set_ylabel("Districts detected (%)")
axes[0].legend(fontsize=8, loc="lower left")
fig.suptitle("Detection of upsurges affecting clusters of neighbouring districts, fixed 2% false-alert rate")
fig.tight_layout()
save(fig, "fig18_cluster_size")

# 19. Documented events -----------------------------------------------------------------------
ev = pd.read_csv("out/real_events_sat-all.csv")
names = pd.read_csv("data/derived/cases_district_month.csv")[["unit", "District"]].drop_duplicates()
ev = ev.merge(names, on="unit", how="left")
SHORT = {"E01": "Bagre spillage, 2018", "E03": "Upper East floods, 2019", "E04": "Upper East floods, 2020",
         "E05": "North East Bagre floods, 2020", "E09": "Bagre spillage, 2021", "E10": "Bagre spillage, 2022",
         "E11": "Black Volta, Buipe, 2022", "E13": "Black Volta, Buipe, 2023",
         "E14": "Akosombo/Kpong spillage, 2023", "E15": "Floods and Bagre, 2024", "E16": "Bagre spillage, 2025",
         "E17": "Accra floods, 2025", "E18": "Press report, 2024", "E19": "Press report, 2025"}
events = [e for e in SHORT if e in set(ev.event)]
fig, ax = plt.subplots(figsize=(10, 7))
rng = np.random.default_rng(1)
for i, e in enumerate(events):
    d = ev[ev.event == e]
    yy = len(events) - 1 - i + rng.uniform(-0.18, 0.18, len(d))
    ax.scatter(d.obs_exp[~d.flagged], yy[~d.flagged.values], facecolors="none", edgecolors="tab:gray", s=30)
    ax.scatter(d.obs_exp[d.flagged], yy[d.flagged.values], color="tab:red", s=34, zorder=3)
    for (_, r), yv in zip(d.iterrows(), yy):
        if r.flagged or r.District == "North Tongu":
            ax.annotate(r.District, (r.obs_exp, yv), xytext=(5, 2), textcoords="offset points", fontsize=7)
ax.scatter([], [], color="tab:red", label="Alert in the event window")
ax.scatter([], [], facecolors="none", edgecolors="tab:gray", label="No alert")
ax.axvline(1, color="black", lw=1, ls="--")
ax.set_xscale("log")
ax.set_xticks([0.7, 1, 1.5, 2])
ax.set_xticklabels(["0.7", "1", "1.5", "2"])
ax.set_yticks(range(len(events)))
ax.set_yticklabels([f"{SHORT[e]} ({(ev.event == e).sum()})" for e in events][::-1])
ax.set_xlabel("Observed / expected confirmed cases over the event window (start month + 2)")
ax.set_title(f"Documented events, 2018-2025: {int(ev.flagged.sum())} of {len(ev)} event-districts with an alert "
             "(final system)")
ax.legend(loc="lower right", fontsize=8)
fig.tight_layout()
save(fig, "fig19_real_events")
