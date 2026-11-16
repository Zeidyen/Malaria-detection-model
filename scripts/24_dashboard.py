"""Prototype dashboard (supplementary material): one self-contained HTML file, no external libraries,
works offline. Retrospective 2018-2025 output of the final system (sat-all).

Run from the project folder:  python3 -I scripts/24_dashboard.py [MODEL=sat-all]
Inputs: monthly predictions (07), alerts with Tier 3 class (08), satellite panel (15), district shapes.
Template: scripts/dashboard_template.html (data are inserted at /*DATA*/).
Output: out/dashboard/ghana_malaria_upsurge_dashboard.html (a new version never overwrites: _v2, ...)
"""
import json
import os
import sys

import numpy as np
import pandas as pd

MODEL = sys.argv[1] if len(sys.argv) > 1 else "sat-all"
tag = "ar" if MODEL == "arm" else MODEL
months = [(y, m) for y in range(2018, 2026) for m in range(1, 13)]

pred = pd.concat([pd.read_csv(f"out/monthly/model_{tag}_{y}_{m:02d}_pred.csv") for y, m in months])
al = pd.read_csv(f"out/alerts_{MODEL}_2018_2025.csv")[["unit", "year", "m", "tier3"]]
pred = pred.merge(al, on=["unit", "year", "m"], how="left")
sat = pd.read_csv("data/derived/satellite_district_month.csv")
pred = pred.merge(sat[["unit", "year", "m", "rain_chirps", "ndvi", "t2m"]], on=["unit", "year", "m"], how="left")
pred["t"] = (pred.year - 2018) * 12 + pred.m - 1
pred = pred.sort_values(["unit", "t"])
CLS = {"transmission": 1, "reporting": 2, "indeterminate": 3}

gj = json.load(open("data/derived/units_simplified.geojson"))
shapes = {}
for f in gj["features"]:
    g = f["geometry"]
    polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
    shapes[f["properties"]["unit"]] = [[[round(x, 3), round(y, 3)] for x, y in ring] for poly in polys for ring in poly[:1]]


def r(a, d=0):
    return [None if pd.isna(v) else (round(float(v), d) if d else int(round(float(v)))) for v in a]


districts = []
for unit, s in pred.groupby("unit", sort=True):
    assert len(s) == 96, unit
    districts.append({
        "id": unit, "name": s.District.iloc[0], "region": s.Region.iloc[0], "zone": s.zone.iloc[0],
        "pop": int(s.pop_tot.iloc[-1]),
        "obs": r(s.conf_tot), "med": r(s.pred_med_adj), "lo": r(s.lo95_adj), "hi": r(s.hi95_adj),
        "cls": [CLS.get(v, 0) if isinstance(v, str) else 0 for v in s.tier3],
        "rain": r(s.rain_chirps), "ndvi": r(s.ndvi, 2), "t2m": r(s.t2m, 1),
        "shape": shapes[unit],
    })
zones = {}
for z, s in pred.groupby("zone"):
    zz = s.groupby("t").agg(o=("conf_tot", "sum"), p=("pred_med", "sum")).reset_index()
    zones[z] = r(zz.o / zz.p, 3)
data = {"model": MODEL, "months": [f"{y}-{m:02d}" for y, m in months], "districts": districts, "zones": zones,
        "n_alerts": int(len(al))}

tpl = open("scripts/dashboard_template.html").read()
html = tpl.replace("/*DATA*/", "const DATA = " + json.dumps(data, separators=(",", ":")) + ";")
os.makedirs("out/dashboard", exist_ok=True)
path, v = "out/dashboard/ghana_malaria_upsurge_dashboard.html", 2
while os.path.exists(path):
    path, v = f"out/dashboard/ghana_malaria_upsurge_dashboard_v{v}.html", v + 1
open(path, "w").write(html)
print("saved", path, f"{os.path.getsize(path) / 1e6:.1f} MB")
