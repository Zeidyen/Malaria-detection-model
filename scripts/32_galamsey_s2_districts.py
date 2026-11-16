"""Sentinel-2 before/after views for every mining district, not only Amansie West (fig14).

Run from the project folder WITHOUT -I (earthengine-api is in the user site-packages):
    python3 scripts/32_galamsey_s2_districts.py --project durable-circle-448314-t3
Districts: the stricter mining definition of 22_galamsey.R (bare-ground share up >= 0.5 points,
2016-2024; 14 districts), ordered by the increase. Same method as fig14 in 19_satellite_rasters.py:
dry-season (Nov-Mar) Cloud Score+ masked median, true colour, one contrast stretch per district
shared by both dates. Resolution is ~30 m, coarsened for large districts to stay within the
computePixels size limit. Rasters cached in data/derived/rasters/s2_<unit>_<period>.npy.
Output: fig22_galamsey_sentinel2_{a,b,c,d} (4 districts each), never overwritten.
"""
import argparse
import math
import os

import geopandas as gpd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

RAS, OUT = "data/derived/rasters", "out/figures"
PERIODS = [("2016_17", "2016-11-01", "2017-04-01", "Nov 2016-Mar 2017"),
           ("2024_25", "2024-11-01", "2025-04-01", "Nov 2024-Mar 2025")]
MAXPX = 1600  # per side; 1600 x 1600 x 3 bands float32 ~ 31 MB, under the 48 MB request limit


def save(fig, name):
    path = os.path.join(OUT, name + ".png")
    v = 2
    while os.path.exists(path):
        path = os.path.join(OUT, f"{name}_v{v}.png")
        v += 1
    fig.savefig(path, dpi=170, bbox_inches="tight")
    plt.close(fig)
    print("saved", path)


def s2(bounds, tag, start, end, maxpx=MAXPX):
    path = os.path.join(RAS, f"s2_{tag}.npy")
    if os.path.exists(path):
        return np.load(path)
    import ee
    x0, y0, x1, y1 = bounds
    res = max(0.00027, (x1 - x0) / maxpx, (y1 - y0) / maxpx)
    nx, ny = int((x1 - x0) / res), int((y1 - y0) / res)
    grid = {"dimensions": {"width": nx, "height": ny},
            "affineTransform": {"scaleX": res, "shearX": 0, "translateX": x0, "shearY": 0, "scaleY": -res,
                                "translateY": y1},
            "crsCode": "EPSG:4326"}
    geom = ee.Geometry.Rectangle([x0, y0, x1, y1])
    csp = ee.ImageCollection("GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED").filterDate(start, end).filterBounds(geom)
    img = (ee.ImageCollection("COPERNICUS/S2_HARMONIZED").filterDate(start, end).filterBounds(geom)
           .linkCollection(csp, ["cs_cdf"])
           .map(lambda i: i.select(["B4", "B3", "B2"]).updateMask(i.select("cs_cdf").gte(0.6)))
           .median().toFloat())
    try:
        a = ee.data.computePixels({"expression": img, "fileFormat": "NUMPY_NDARRAY", "grid": grid})
    except ee.EEException as err:  # memory limit on scenes with many images: retry coarser
        if "memory" not in str(err) or maxpx < 600:
            raise
        print(f"{tag}: {err}; retrying at {int(maxpx * 0.7)} px")
        return s2(bounds, tag, start, end, int(maxpx * 0.7))
    arr = np.stack([a[b].astype(float) for b in a.dtype.names], axis=-1)
    np.save(path, arr)
    print(f"fetched {tag} {arr.shape} at {res * 111000:.0f} m")
    return arr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=None)
    a = ap.parse_args()
    if a.project:
        import ee
        ee.Initialize(project=a.project)
    units = gpd.read_file("data/derived/units_simplified.geojson")
    ex = pd.read_csv("out/galamsey_exposure.csv")
    ex = ex[ex.d_bare >= 0.005].sort_values("d_bare", ascending=False)
    print(len(ex), "districts")

    per = 4
    for k in range(math.ceil(len(ex) / per)):
        chunk = ex.iloc[k * per:(k + 1) * per]
        rows = math.ceil(len(chunk) / 2)
        fig, axes = plt.subplots(rows, 4, figsize=(18, 4.6 * rows), squeeze=False)
        for j, (_, d) in enumerate(chunk.iterrows()):
            g = units[units.unit == d.unit]
            x0, y0, x1, y1 = g.total_bounds
            pad = 0.02
            b = (x0 - pad, y0 - pad, x1 + pad, y1 + pad)
            imgs = [s2(b, f"{d.unit}_{t}", s, e) for t, s, e, _ in PERIODS]
            lo, hi = np.nanpercentile(np.concatenate([i.ravel() for i in imgs]), [1, 99])
            for p, (z, (_, _, _, lab)) in enumerate(zip(imgs, PERIODS)):
                ax = axes[j // 2, (j % 2) * 2 + p]
                rgb = np.clip((z - lo) / (hi - lo), 0, 1) ** (1 / 1.3)
                ax.imshow(np.where(np.isnan(rgb), 1, rgb), extent=(b[0], b[2], b[1], b[3]), interpolation="nearest")
                units.boundary.plot(ax=ax, color="white", linewidth=0.4)
                g.boundary.plot(ax=ax, color="yellow", linewidth=1.3)
                ax.set_xlim(b[0], b[2])
                ax.set_ylim(b[1], b[3])
                ax.set_xticks([])
                ax.set_yticks([])
                ax.set_title(f"{d.District} ({d.Region}), {lab}\nbare ground {100 * d.bare_2016:.1f}% (2016) "
                             f"to {100 * d.bare_2024:.1f}% (2024)" if p == 0 else
                             f"{d.District}, {lab}", fontsize=9)
        for ax in axes.flat[len(chunk) * 2:]:
            ax.axis("off")
        fig.suptitle("Mining districts (yellow outline): Sentinel-2 true colour, dry-season cloud-masked median, "
                     "2016-17 (left) vs 2024-25 (right) for each district", fontsize=11)
        fig.tight_layout()
        save(fig, f"fig22_galamsey_sentinel2_{'abcd'[k]}")


if __name__ == "__main__":
    main()
