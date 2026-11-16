"""Descriptive figures of the satellite and climate layers (plain matplotlib).

Input: data/derived/satellite_district_month.csv (15_satellite_panel.R), cases_district_month.csv.
Figures go to out/figures/; an existing figure is never overwritten (_v2, _v3, ...).
Run from the project folder:  python3 -I scripts/18_satellite_figures.py
  fig8   maps of the 2015-2025 district mean of six layers
  fig9   monthly zone means 2015-2025 of the climate layers, with confirmed cases per 1,000
  fig10  mean seasonal cycle by zone: rainfall, soil moisture, NDVI and cases (each scaled 0-1)
  fig11  Dynamic World land cover change 2016 -> 2024, per district (trees, bare, built)
"""
import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.collections import PolyCollection

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


ZONE = {"Upper West": "North", "Upper East": "North", "North East": "North", "Northern": "North",
        "Savannah": "North", "Ashanti": "Forest", "Bono": "Forest", "Bono East": "Forest",
        "Ahafo": "Forest", "Eastern": "Forest", "Western North": "Forest", "Oti": "Forest",
        "Greater Accra": "Coast", "Central": "Coast", "Western": "Coast", "Volta": "Coast"}
ZONES = ["North", "Forest", "Coast"]

sat = pd.read_csv("data/derived/satellite_district_month.csv")
cases = pd.read_csv("data/derived/cases_district_month.csv")
d = sat.merge(cases[["unit", "Region", "year", "m", "pop_tot", "conf_tot"]], on=["unit", "year", "m"])
d["zone"] = d.Region.map(ZONE)
d["date"] = pd.to_datetime(dict(year=d.year, month=d.m, day=15))
d["inc"] = d.conf_tot / d.pop_tot * 1000

gj = json.load(open("data/derived/units_simplified.geojson"))
polys, punit = [], []
for f in gj["features"]:
    g = f["geometry"]
    rings = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
    for poly in rings:
        polys.append(np.array(poly[0]))
        punit.append(f["properties"]["unit"])


def draw_map(ax, values, title, label, cmap="viridis", vmin=None, vmax=None):
    pc = PolyCollection(polys, array=np.array([values.get(u, np.nan) for u in punit]), cmap=cmap,
                        edgecolor="white", linewidth=0.15)
    pc.set_clim(vmin, vmax)
    ax.add_collection(pc)
    ax.autoscale_view()
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_title(title, fontsize=10)
    plt.colorbar(pc, ax=ax, label=label, shrink=0.75)


# 8. Maps of district means, 2015-2025 --------------------------------------------------------
annual_rain = d.groupby(["unit", "year"]).rain_chirps.sum().groupby("unit").mean()
mean = d.groupby("unit").mean(numeric_only=True)
panels = [(annual_rain, "Rainfall (CHIRPS)", "mm per year", "viridis"),
          (mean.lst_day, "Land surface temperature, day (MODIS)", "deg C", "viridis"),
          (mean.soil_moisture, "Soil moisture (SMAP)", "m3/m3", "viridis"),
          (mean.ndvi, "NDVI (MODIS)", "NDVI", "viridis"),
          (mean.dw_trees * 100 if "dw_trees" in mean else None, "", "", "viridis"),
          (mean.log_nl, "Night lights (VIIRS)", "log(1 + radiance)", "viridis")]
dw = pd.concat(pd.read_csv(f"data/derived/gee/dynworld_{y}.csv") for y in range(2016, 2026))
dw = dw.pivot_table(index=["unit", "year"], columns="variable", values="value").reset_index()
panels[4] = (dw.groupby("unit").dw_trees.mean() * 100, "Tree cover (Dynamic World)", "% of area", "viridis")
fig, axes = plt.subplots(2, 3, figsize=(13, 10))
for ax, (v, t, lab, cm) in zip(axes.flat, panels):
    draw_map(ax, v, t, lab, cm)
fig.suptitle("District means of the satellite layers, 2015-2025 (tree cover 2016-2025)")
save(fig, "fig8_satellite_maps")

# 9. Monthly zone means over time ------------------------------------------------------------
z = (d.assign(w=d.pop_tot).groupby(["zone", "date"])
     .apply(lambda g: pd.Series({v: np.average(g[v], weights=g.w) for v in
                                 ["rain_chirps", "lst_day", "soil_moisture", "ndvi", "rh"]} |
                                {"inc": g.conf_tot.sum() / g.pop_tot.sum() * 1000}), include_groups=False)
     .reset_index())
rows = [("inc", "Confirmed cases per 1,000"), ("rain_chirps", "Rainfall (mm/month)"),
        ("soil_moisture", "Soil moisture (m3/m3)"), ("ndvi", "NDVI"), ("lst_day", "LST day (deg C)"),
        ("rh", "Relative humidity (%)")]
fig, axes = plt.subplots(len(rows), 1, figsize=(11, 13), sharex=True)
for ax, (v, lab) in zip(axes, rows):
    for zn in ZONES:
        s = z[z.zone == zn]
        ax.plot(s.date, s[v], lw=1, label=zn)
    ax.set_ylabel(lab, fontsize=9)
axes[0].legend(ncol=3, frameon=False, loc="upper left")
axes[-1].set_xlabel("Month")
fig.suptitle("Malaria cases and climate layers by ecological zone, 2015-2025 (population-weighted means)")
fig.tight_layout()
save(fig, "fig9_satellite_timeseries")

# 10. Mean seasonal cycle by zone, each series scaled 0-1 -----------------------------------------
fig, axes = plt.subplots(1, 3, figsize=(13, 4), sharey=True)
z["m"] = z.date.dt.month
for ax, zn in zip(axes, ZONES):
    s = z[z.zone == zn].groupby("m").mean(numeric_only=True)
    for v, lab, ls in [("inc", "Cases per 1,000", "-"), ("rain_chirps", "Rainfall", "--"),
                       ("soil_moisture", "Soil moisture", "-."), ("ndvi", "NDVI", ":")]:
        x = s[v]
        ax.plot(s.index, (x - x.min()) / (x.max() - x.min()), ls=ls, lw=1.5, label=lab)
    ax.set_title(zn)
    ax.set_xticks(range(1, 13))
    ax.set_xticklabels(list("JFMAMJJASOND"))
    ax.set_xlabel("Month")
axes[0].set_ylabel("Scaled 0 (lowest month) to 1 (highest)")
axes[0].legend(frameon=False, fontsize=8)
fig.suptitle("Average seasonal cycle, 2015-2025")
fig.tight_layout()
save(fig, "fig10_seasonal_cycle")

# 11. Land-cover change 2016 -> 2024 -------------------------------------------------------------
a = dw[dw.year == 2016].set_index("unit")
b = dw[dw.year == 2024].set_index("unit")
fig, axes = plt.subplots(1, 3, figsize=(13, 5.5))
for ax, (v, t) in zip(axes, [("dw_trees", "Trees"), ("dw_bare", "Bare ground"), ("dw_built", "Built-up")]):
    ch = (b[v] - a[v]) * 100
    lim = np.nanpercentile(np.abs(ch), 98)
    draw_map(ax, ch, f"{t}: change 2016 to 2024", "percentage points", "RdBu_r", vmin=-lim, vmax=lim)
fig.suptitle("Dynamic World land-cover change per district (annual cloud-masked label shares)")
save(fig, "fig11_landcover_change")

# 12. Value of the satellite layers: outbreak sensitivity at a fixed 2% false-alert rate (17) ------
if os.path.exists("out/satellite_value.csv"):
    sv = pd.read_csv("out/satellite_value.csv").set_index("model")
    names = {"arm": "Main model (no satellite)", "sat-rain": "+ rainfall (CHIRPS)", "sat-sm": "+ soil moisture (SMAP)",
             "sat-env": "+ land cover, night lights", "sat-lst": "+ land surface temp. (MODIS)",
             "sat-ndvi": "+ NDVI (MODIS)", "sat-era5": "+ temperature, humidity (ERA5)", "sat-all": "+ all layers"}
    order = ["arm", "sat-sm", "sat-env", "sat-rain", "sat-lst", "sat-ndvi", "sat-era5", "sat-all"]
    cells = [("+25%_1mo", "+25%, 1 month"), ("+25%_3mo", "+25%, 3 months"), ("+50%_1mo", "+50%, 1 month"),
             ("+50%_3mo", "+50%, 3 months"), ("+100%_1mo", "doubling, 1 month"), ("+100%_3mo", "doubling, 3 months")]
    fig, axes = plt.subplots(1, 6, figsize=(15, 4.5), sharey=True)
    y = np.arange(len(order))
    for ax, (c, t) in zip(axes, cells):
        v = sv.loc[order, c] * 100
        ax.barh(y, v, color=["grey"] + ["tab:blue"] * (len(order) - 2) + ["tab:red"])
        ax.axvline(v.iloc[0], color="grey", lw=0.8, ls="--")
        ax.set_title(t, fontsize=10)
        ax.set_xlabel("Detected (%)")
    axes[0].set_yticks(y)
    axes[0].set_yticklabels([names[o] for o in order])
    fig.suptitle("Injected malaria upsurges detected at a fixed 2% false-alert rate, 2018-2025, by satellite layers added")
    fig.tight_layout()
    save(fig, "fig12_satellite_value")

# 15. Galamsey: bare-ground increase per forest-belt district, and incidence in mining vs other (22) --
if os.path.exists("out/galamsey_exposure.csv"):
    ex = pd.read_csv("out/galamsey_exposure.csv")
    ex["mining05"] = ex.d_bare >= 0.005
    fig, axes = plt.subplots(1, 2, figsize=(14, 6), gridspec_kw={"width_ratios": [1, 1.2]})
    ax = axes[0]
    vals = (ex.set_index("unit").d_bare * 100).to_dict()
    pc = PolyCollection([p for p, u in zip(polys, punit) if u in vals],
                        array=np.array([vals[u] for u in punit if u in vals]), cmap="Reds",
                        edgecolor="grey", linewidth=0.2)
    pc.set_clim(0, np.percentile(list(vals.values()), 98))
    ax.add_collection(pc)
    mine = set(ex.unit[ex.mining05])
    ax.add_collection(PolyCollection([p for p, u in zip(polys, punit) if u in mine], facecolor="none",
                                     edgecolor="black", linewidth=1.2))
    ax.add_collection(PolyCollection(polys, facecolor="none", edgecolor="lightgrey", linewidth=0.1))
    ax.autoscale_view()
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_title("Increase in bare-ground share 2016-2024, forest belt\n(black outline: >= 0.5 points, 14 districts)", fontsize=10)
    plt.colorbar(pc, ax=ax, label="percentage points (Dynamic World)", shrink=0.7)
    ax = axes[1]
    c = cases[cases.Region.isin(["Ashanti", "Western", "Western North", "Eastern", "Central"])].copy()
    c["grp"] = np.where(c.unit.isin(mine), "Mining districts (14)", "Other forest-belt districts")
    g = c.groupby(["year", "grp"]).agg(conf=("conf_tot", "sum"), pop=("pop_tot", "mean"), n=("unit", "nunique")).reset_index()
    g["inc"] = g.conf / (g["pop"] * g.n) * 1000
    for grp, s in g.groupby("grp"):
        ax.plot(s.year, s.inc, marker="o", label=grp)
    ax.set_xlabel("Year")
    ax.set_ylabel("Confirmed malaria cases per 1,000 per year")
    ax.set_title("Malaria incidence, forest belt, 2015-2025", fontsize=10)
    ax.legend(frameon=False)
    fig.tight_layout()
    save(fig, "fig15_galamsey")
