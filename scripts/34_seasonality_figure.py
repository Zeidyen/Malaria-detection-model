"""Figure for 33_seasonality_climate.R (plain matplotlib).
Run from the project folder:  python3 -I scripts/34_seasonality_figure.py
  fig23_seasonality_climate  top: zone mean monthly incidence and rainfall, 2015-2025;
                             bottom: model seasonal term without climate (M0) and with all climate and
                             environment terms (M4), and the seasonal pattern implied by the climate terms
Never overwrites: _v2, _v3, ...
"""
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker
import numpy as np
import pandas as pd

OUT = "out/figures"


def save(fig, name):
    path = os.path.join(OUT, name + ".png")
    v = 2
    while os.path.exists(path):
        path = os.path.join(OUT, f"{name}_v{v}.png")
        v += 1
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)
    print("saved", path)


cl = pd.read_csv("out/seasonality_climatology.csv")
T = pd.read_csv("out/seasonality_terms.csv")
A = pd.read_csv("out/seasonality_amplitude.csv")
MON = list("JFMAMJJASOND")
fig, axes = plt.subplots(2, 3, figsize=(15, 8))
for j, z in enumerate(["North", "Forest", "Coast"]):
    c = cl[cl.zone == z]
    ax = axes[0, j]
    ax2 = ax.twinx()
    ax2.bar(c.m, c.rain_chirps, color="tab:blue", alpha=0.3, label="Rainfall")
    ax.plot(c.m, c.inc_per_1000, "o-", color="tab:red", label="Confirmed cases")
    ax.set_zorder(ax2.get_zorder() + 1)
    ax.patch.set_visible(False)
    ax.set_title(z)
    ax.set_xticks(range(1, 13), MON)
    ax.set_ylabel("Confirmed cases per 1,000 per month")
    ax2.set_ylabel("Rainfall (mm per month)")
    ax.set_ylim(0, None)
    if j == 0:
        h1, l1 = ax.get_legend_handles_labels()
        h2, l2 = ax2.get_legend_handles_labels()
        ax.legend(h1 + h2, l1 + l2, loc="upper left", fontsize=8)
    ax = axes[1, j]
    for mod, col, lab in [("M0_none", "black", "Seasonal term, no climate terms"),
                          ("M4_climate_env", "tab:red", "Seasonal term, with climate terms")]:
        t = T[(T.model == mod) & (T.zone == z)]
        ax.fill_between(t.m, np.exp(t.lo), np.exp(t.hi), color=col, alpha=0.12, lw=0)
        ax.plot(t.m, np.exp(t.est), "o-", color=col, ms=3, label=lab)
    t = T[(T.model == "M4_climate_env") & (T.zone == z)]
    ax.plot(t.m, np.exp(t.clim_lp), "s--", color="tab:blue", ms=3, label="Part due to climate terms")
    ax.axhline(1, color="gray", lw=0.8)
    ax.set_yscale("log")
    ticks = [0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.25, 1.5, 2]
    ax.set_yticks(ticks, [f"{t:g}" for t in ticks])
    ax.yaxis.set_minor_locator(matplotlib.ticker.NullLocator())
    ax.set_xticks(range(1, 13), MON)
    ax.set_ylabel("Rate ratio vs zone's average month")
    s = A[(A.model == "M4_climate_env") & (A.zone == z)].share_taken_by_climate.iloc[0]
    ax.set_title(f"{z}: {100 * s:.0f}% of the seasonal range taken over by climate terms", fontsize=10)
    if j == 0:
        ax.legend(fontsize=8, loc="upper left")
fig.suptitle("Seasonality of confirmed malaria cases and climate, by zone, 2015-2025")
fig.tight_layout()
save(fig, "fig23_seasonality_climate")
