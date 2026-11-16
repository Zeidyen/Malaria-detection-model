"""Pixel-level maps of the satellite layers (study-area figures), plain matplotlib.

Run from the project folder WITHOUT -I (earthengine-api is in the user site-packages):
    python3 scripts/19_satellite_rasters.py --project durable-circle-448314-t3
Rasters are downloaded once with ee.data.computePixels and cached in data/derived/rasters/*.npy,
so later runs only re-plot. Figures go to out/figures/ (never overwritten: _v2, _v3, ...).

  fig13  national maps at ~1 km (0.01 deg): mean annual rainfall (CHIRPS), mean 2 m temperature and
         relative humidity (ERA5-Land monthly), mean daytime land surface temperature (MODIS), NDVI in
         the dry (Jan) and wet (Sep) season (MODIS), night lights 2024 (VIIRS), land cover 2024
         (Dynamic World, most frequent cloud-free label). Means are over 2015-2025.
  fig14  Sentinel-2 true colour around Amansie West (Ashanti), dry season 2016-17 vs 2024-25, 30 m,
         Cloud Score+ masked median. Visual context for the galamsey analysis (DESIGN.md s6b).
"""
import argparse
import os

import geopandas as gpd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import ListedColormap
from matplotlib.patches import Patch

RAS = "data/derived/rasters"
OUT = "out/figures"
os.makedirs(RAS, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

# national grid: 0.01 deg (~1.1 km)
X0, Y1, RES = -3.35, 11.25, 0.01
NX, NY = 470, 670
EXTENT = (X0, X0 + NX * RES, Y1 - NY * RES, Y1)

DW_NAMES = ["water", "trees", "grass", "flooded vegetation", "crops", "shrub and scrub", "built",
            "bare", "snow and ice"]
DW_COLS = ["#419bdf", "#397d49", "#88b053", "#7a87c6", "#e49635", "#dfc35a", "#c4281b", "#a59b8f",
           "#b39fe1"]


def save(fig, name):
    path = os.path.join(OUT, name + ".png")
    v = 2
    while os.path.exists(path):
        path = os.path.join(OUT, f"{name}_v{v}.png")
        v += 1
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)
    print("saved", path)


def fetch(name, image_fn, grid):
    """image_fn() -> single-band ee.Image; cached as .npy."""
    path = os.path.join(RAS, name + ".npy")
    if os.path.exists(path):
        arr = np.load(path)
        return arr[..., 0] if arr.shape[-1] == 1 else arr
    import ee
    img = image_fn().toFloat()
    arr = ee.data.computePixels({"expression": img, "fileFormat": "NUMPY_NDARRAY", "grid": grid})
    arr = np.array(arr.tolist(), dtype=float) if arr.dtype.names is None else \
        np.stack([arr[b].astype(float) for b in arr.dtype.names], axis=-1)
    np.save(path, arr)
    print("fetched", name, arr.shape)
    return arr[..., 0] if arr.shape[-1] == 1 else arr


def national_layers():
    import ee
    grid = {"dimensions": {"width": NX, "height": NY},
            "affineTransform": {"scaleX": RES, "shearX": 0, "translateX": X0,
                                "shearY": 0, "scaleY": -RES, "translateY": Y1},
            "crsCode": "EPSG:4326"}
    yrs = ("2015-01-01", "2026-01-01")
    era = lambda: ee.ImageCollection("ECMWF/ERA5_LAND/MONTHLY_AGGR").filterDate(*yrs)   # lazy: cached runs need no EE

    def rh(i):
        t = i.select("temperature_2m").subtract(273.15)
        td = i.select("dewpoint_temperature_2m").subtract(273.15)
        e = td.multiply(17.625).divide(td.add(243.04)).exp()
        es = t.multiply(17.625).divide(t.add(243.04)).exp()
        return e.divide(es).multiply(100)

    def ndvi(month):
        return (ee.ImageCollection("MODIS/061/MOD13A3").filterDate(*yrs)
                .filter(ee.Filter.calendarRange(month, month, "month")).select("NDVI").mean().multiply(1e-4))

    def dw2024():
        csp = ee.ImageCollection("GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED").filterDate("2024-01-01", "2025-01-01")
        c = (ee.ImageCollection("GOOGLE/DYNAMICWORLD/V1").filterDate("2024-01-01", "2025-01-01")
             .filterBounds(ee.Geometry.Rectangle([-3.4, 4.6, 1.3, 11.2]))
             .linkCollection(csp, ["cs_cdf"])
             .map(lambda i: i.select("label").updateMask(i.select("cs_cdf").gte(0.6))))
        return c.mode()

    L = {
        "rain": lambda: ee.ImageCollection("UCSB-CHG/CHIRPS/PENTAD").filterDate(*yrs).select("precipitation").sum().divide(11),
        "t2m": lambda: era().select("temperature_2m").mean().subtract(273.15),
        "rh": lambda: era().map(rh).mean(),
        "lst": lambda: ee.ImageCollection("MODIS/061/MOD11A2").filterDate(*yrs).select("LST_Day_1km").mean().multiply(0.02).subtract(273.15),
        "ndvi_jan": lambda: ndvi(1),
        "ndvi_sep": lambda: ndvi(9),
        "nl": lambda: ee.ImageCollection("NOAA/VIIRS/DNB/MONTHLY_V1/VCMSLCFG").filterDate("2024-01-01", "2025-01-01").select("avg_rad").median(),
        "dw": dw2024,
    }
    return {k: fetch("ghana_" + k, f, grid) for k, f in L.items()}


def s2_window(bounds, tag, start, end):
    import ee
    x0, y0, x1, y1 = bounds
    res = 0.00027  # ~30 m
    nx, ny = int((x1 - x0) / res), int((y1 - y0) / res)
    grid = {"dimensions": {"width": nx, "height": ny},
            "affineTransform": {"scaleX": res, "shearX": 0, "translateX": x0, "shearY": 0, "scaleY": -res, "translateY": y1},
            "crsCode": "EPSG:4326"}

    def img():
        geom = ee.Geometry.Rectangle([x0, y0, x1, y1])
        csp = ee.ImageCollection("GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED").filterDate(start, end).filterBounds(geom)
        c = (ee.ImageCollection("COPERNICUS/S2_HARMONIZED").filterDate(start, end).filterBounds(geom)
             .linkCollection(csp, ["cs_cdf"])
             .map(lambda i: i.select(["B4", "B3", "B2"]).updateMask(i.select("cs_cdf").gte(0.6))))
        return c.median()

    return fetch(f"s2_{tag}", img, grid)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=None, help="Earth Engine project (only needed for the first download)")
    a = ap.parse_args()
    if a.project:
        import ee
        ee.Initialize(project=a.project)

    units = gpd.read_file("data/derived/units_simplified.geojson")
    regions = units.dissolve("Region")
    outside = gpd.GeoSeries([units.union_all()], crs=units.crs)

    def outline(ax):
        units.boundary.plot(ax=ax, color="white", linewidth=0.15, alpha=0.6)
        regions.boundary.plot(ax=ax, color="black", linewidth=0.5)
        ax.set_xlim(EXTENT[0], EXTENT[1])
        ax.set_ylim(EXTENT[2], EXTENT[3])
        ax.set_xticks([])
        ax.set_yticks([])

    # mask pixels outside Ghana
    from shapely import contains_xy
    xs = X0 + (np.arange(NX) + 0.5) * RES
    ys = Y1 - (np.arange(NY) + 0.5) * RES
    XX, YY = np.meshgrid(xs, ys)
    inside = contains_xy(outside.iloc[0], XX, YY)

    r = national_layers()
    panels = [("rain", "Rainfall, mean annual total (CHIRPS)", "mm per year", "viridis_r", None),
              ("t2m", "Air temperature at 2 m, mean (ERA5-Land)", "deg C", "inferno", None),
              ("rh", "Relative humidity, mean (ERA5-Land)", "%", "viridis_r", None),
              ("lst", "Land surface temperature, day (MODIS)", "deg C", "inferno", None),
              ("ndvi_jan", "NDVI, January (dry season, MODIS)", "NDVI", "YlGn", (0, 0.85)),
              ("ndvi_sep", "NDVI, September (rainy season, MODIS)", "NDVI", "YlGn", (0, 0.85)),
              ("nl", "Night lights, 2024 median (VIIRS)", "radiance (log scale)", "magma", None)]
    fig, axes = plt.subplots(2, 4, figsize=(16, 11))
    for ax, (k, t, lab, cm, lim) in zip(axes.flat, panels):
        z = np.where(inside, r[k], np.nan)
        if k == "nl":
            z = np.log10(np.clip(z, 0.1, None))
        lo, hi = lim if lim else np.nanpercentile(z, [1, 99])
        im = ax.imshow(z, extent=EXTENT, cmap=cm, vmin=lo, vmax=hi, interpolation="nearest")
        outline(ax)
        ax.set_title(t, fontsize=10)
        cb = fig.colorbar(im, ax=ax, shrink=0.7)
        cb.set_label(lab)
        if k == "nl":
            ticks = [-1, 0, 1, 2]
            cb.set_ticks(ticks)
            cb.set_ticklabels(["0.1", "1", "10", "100"])
    ax = axes.flat[7]
    dw = np.where(inside & ~np.isnan(r["dw"]), r["dw"], np.nan)
    ax.imshow(dw, extent=EXTENT, cmap=ListedColormap(DW_COLS), vmin=-0.5, vmax=8.5, interpolation="nearest")
    outline(ax)
    ax.set_title("Land cover, 2024 (Dynamic World)", fontsize=10)
    present = [i for i in range(9) if np.any(dw == i) and i != 8]
    ax.legend(handles=[Patch(color=DW_COLS[i], label=DW_NAMES[i]) for i in present], fontsize=7,
              loc="lower left", bbox_to_anchor=(1.0, 0.0), frameon=False)
    fig.suptitle("Satellite and climate layers over Ghana, 2015-2025 (black lines: regions; white: districts)")
    fig.tight_layout()
    save(fig, "fig13_satellite_layers_pixel")

    # Sentinel-2 close-up, Amansie West
    aw = units[units.unit == "amansiewest"]
    x0, y0, x1, y1 = aw.total_bounds
    pad = 0.03
    b = (x0 - pad, y0 - pad, x1 + pad, y1 + pad)
    pairs = [("amansiewest_2016_17", "2016-11-01", "2017-04-01", "Nov 2016 - Mar 2017"),
             ("amansiewest_2024_25", "2024-11-01", "2025-04-01", "Nov 2024 - Mar 2025")]
    imgs = [s2_window(b, tag, s, e) for tag, s, e, _ in pairs]
    # one contrast stretch for both dates and all three bands (1st-99th percentile, pooled), so the
    # two panels stay comparable and colours stay natural; it reduces the Harmattan haze cast
    lo, hi = np.nanpercentile(np.concatenate([i.ravel() for i in imgs]), [1, 99])
    fig, axes = plt.subplots(1, 2, figsize=(14, 7.5))
    for ax, z, (tag, s, e, lab) in zip(axes, imgs, pairs):
        rgb = np.clip((z - lo) / (hi - lo), 0, 1) ** (1 / 1.3)
        rgb = np.where(np.isnan(rgb), 1, rgb)
        ax.imshow(rgb, extent=(b[0], b[2], b[1], b[3]), interpolation="nearest")
        units.boundary.plot(ax=ax, color="white", linewidth=0.6)
        aw.boundary.plot(ax=ax, color="yellow", linewidth=1.5)
        ax.set_xlim(b[0], b[2])
        ax.set_ylim(b[1], b[3])
        ax.set_title(f"Sentinel-2 true colour, {lab}", fontsize=11)
        ax.set_xlabel("Longitude")
        ax.set_ylabel("Latitude")
    fig.suptitle("Amansie West district (yellow), Ashanti: dry-season composites, cloud-masked median, 30 m, same contrast stretch")
    fig.tight_layout()
    save(fig, "fig14_amansiewest_sentinel2")


if __name__ == "__main__":
    main()
