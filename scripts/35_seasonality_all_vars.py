"""Seasonal cycle of confirmed cases against every climate and satellite variable, by zone (plain
matplotlib). Companion to fig23 (rainfall only). Data from 33_seasonality_climate.R.
Run from the project folder:  python3 -I scripts/35_seasonality_all_vars.py
  fig24_seasonality_all_variables  rows = variables, columns = zones; red line = cases per 1,000
                                   (left axis), blue = variable (right axis); panel title gives the
                                   correlation of the two cycles at the best lag (variable leading)
Never overwrites: _v2, _v3, ...
"""
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

OUT = "out/figures"


def save(fig, name):
    path = os.path.join(OUT, name + ".png")
    v = 2
    while os.path.exists(path):
        path = os.path.join(OUT, f"{name}_v{v}.png")
        v += 1
    fig.savefig(path, dpi=170, bbox_inches="tight")
    plt.close(fig)
    print("saved", path)


cl = pd.read_csv("out/seasonality_climatology.csv")
xc = pd.read_csv("out/seasonality_xcorr.csv")
VARS = [("rain_chirps", "Rainfall (mm/month)"), ("soil_moisture", "Soil moisture (m³/m³)"),
        ("ndvi", "Vegetation, NDVI"), ("rh", "Relative humidity (%)"),
        ("t2m", "Air temperature, 2 m (°C)"), ("lst_day", "Land surface temp., day (°C)"),
        ("lst_night", "Land surface temp., night (°C)")]
ZONES = ["North", "Forest", "Coast"]
MON = list("JFMAMJJASOND")
fig, axes = plt.subplots(len(VARS), 3, figsize=(15, 3.0 * len(VARS)))
for i, (v, lab) in enumerate(VARS):
    for j, z in enumerate(ZONES):
        c = cl[cl.zone == z]
        ax = axes[i, j]
        ax.plot(c.m, c.inc_per_1000, "o-", color="tab:red", ms=3)
        ax2 = ax.twinx()
        ax2.plot(c.m, c[v], "s--", color="tab:blue", ms=3)
        ax.set_xticks(range(1, 13), MON)
        ax.tick_params(axis="y", colors="tab:red", labelsize=8)
        ax2.tick_params(axis="y", colors="tab:blue", labelsize=8)
        x = xc[(xc.zone == z) & (xc.variable == v)]
        b = x.loc[x.r.abs().idxmax()]
        ax.set_title(f"{z}: {lab}\nr = {b.r:.2f}, variable leading by {int(b.lag)} month(s)", fontsize=9)
        if j == 0:
            ax.set_ylabel("Cases per 1,000", color="tab:red", fontsize=8)
        if j == 2:
            ax2.set_ylabel(lab, color="tab:blue", fontsize=8)
fig.suptitle("Seasonal cycle of confirmed malaria cases (red, left axis) and each climate or satellite "
             "variable (blue, right axis), monthly means 2015-2025", y=1.0)
fig.tight_layout()
save(fig, "fig24_seasonality_all_variables")
