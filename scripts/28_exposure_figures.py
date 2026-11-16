"""Exposure-response figures from 27_exposure_response.R (plain matplotlib).

Run from the project folder:  python3 -I scripts/28_exposure_figures.py
  fig20_exposure_response   cumulative rate ratio over lags 0-3 across each climate variable's range,
                            centred at its median, 95% credible band
  fig21_lag_response        rate ratio at each lag (0-3 months), 90th and 10th percentile vs median
Figures are never overwritten: a new version gets _v2, _v3, ...
"""
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
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


LAB = {"rain_chirps": ("Rainfall", "mm per month"), "lst_day": ("Land surface temperature, day", "°C"),
       "lst_night": ("Land surface temperature, night", "°C"), "soil_moisture": ("Soil moisture", "m³/m³"),
       "ndvi": ("Vegetation (NDVI)", "index"), "t2m": ("Air temperature (ERA5-Land)", "°C"),
       "rh": ("Relative humidity (ERA5-Land)", "%")}
ORDER = ["t2m", "rh", "ndvi", "lst_day", "lst_night", "rain_chirps", "soil_moisture"]

cum = pd.read_csv("out/exposure_response_cumulative.csv")
lag = pd.read_csv("out/exposure_response_lag.csv")

fig, axes = plt.subplots(2, 4, figsize=(16, 7.5))
for ax, v in zip(axes.flat, ORDER):
    d = cum[cum.variable == v]
    med = lag[lag.variable == v]["median"].iloc[0]
    ax.fill_between(d.value, d.lo, d.hi, color="tab:blue", alpha=0.25, lw=0)
    ax.plot(d.value, d.rr, color="tab:blue")
    ax.axhline(1, color="black", lw=0.8)
    ax.axvline(med, color="gray", lw=0.8, ls="--")
    ax.set_title(LAB[v][0], fontsize=10)
    ax.set_xlabel(LAB[v][1])
for ax in axes[:, 0]:
    ax.set_ylabel("Rate ratio vs median, lags 0-3 combined")
axes.flat[-1].axis("off")
fig.suptitle("Association between climate and satellite variables and confirmed malaria cases "
             "(cumulative over lags 0-3 months; 95% credible band; dashed line = median)")
fig.tight_layout()
save(fig, "fig20_exposure_response")

fig, axes = plt.subplots(2, 4, figsize=(16, 7.5), sharey=True)
for ax, v in zip(axes.flat, ORDER):
    for con, c, dx in [("P90 vs median", "tab:red", 0.08), ("P10 vs median", "tab:blue", -0.08)]:
        d = lag[(lag.variable == v) & (lag.contrast == con)]
        ax.errorbar(d.lag + dx, d.rr, yerr=[d.rr - d.lo, d.hi - d.rr], fmt="o", color=c, capsize=3,
                    label=f"{'90th' if con.startswith('P90') else '10th'} percentile "
                          f"({d.value.iloc[0]:.3g}) vs median ({d['median'].iloc[0]:.3g})")
    ax.axhline(1, color="black", lw=0.8)
    ax.set_xticks([0, 1, 2, 3])
    ax.set_xlabel("Lag (months)")
    ax.set_title(LAB[v][0], fontsize=10)
    ax.legend(fontsize=7, loc="upper left")
for ax in axes[:, 0]:
    ax.set_ylabel("Rate ratio")
axes.flat[-1].axis("off")
fig.suptitle("Lag-specific rate ratios: high (90th percentile) and low (10th percentile) values vs the median")
fig.tight_layout()
save(fig, "fig21_lag_response")
