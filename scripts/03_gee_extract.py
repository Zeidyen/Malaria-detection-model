"""Satellite and reanalysis layers -> district-month table, via Google Earth Engine.

Climate layers are POPULATION-WEIGHTED means over the district (WorldPop 100 m as weights),
so they describe where people live rather than the empty parts of the district. Land-cover
and water layers are plain AREA shares, because population weighting would drop exactly
the pixels (water, bare ground) that nobody lives on. See LAYERS below.

Setup (once):
    pip install earthengine-api
    earthengine authenticate
    python3 scripts/03_gee_extract.py --project YOUR-CLOUD-PROJECT

Input : data/derived/units_simplified.geojson (from 02_units.R, 247 units)
Output: data/derived/gee/<layer>_<year>.csv, one row per unit x month. Re-running skips
        files that already exist, so an interrupted run can simply be restarted.

Layers (monthly, 2015-2025 unless noted):
    lst_day, lst_night  MODIS MOD11A2 v061, 1 km, 8-day -> monthly mean, deg C
    ndvi, evi           MODIS MOD13A3 v061, 1 km, monthly
    rain_chirps         CHIRPS daily -> monthly total, mm
    rain_imerg          GPM IMERG V07 monthly -> mm per month
    soil_moisture       SMAP L4 sm_surface, 9 km, 3-hourly -> monthly mean, m3/m3 (from Apr 2015)
    t2m, rh, rain_era5  ERA5-Land monthly: air temperature (deg C), relative humidity (%)
                        from temperature and dewpoint, precipitation (mm)
    water_frac          JRC GSW monthly history: share of observed pixels that are water
                        (ends Dec 2021 in v1.4)
    nightlights         VIIRS DNB monthly, cloud-free, avg radiance
    dw_*                Dynamic World ANNUAL class shares, cloud-masked label composite (water, trees, grass, flooded
                        vegetation, crops, shrub, built, bare), 10 m, from Jul 2015
    s1_water_frac       Sentinel-1 radar open-water share; works through cloud
    pop_near_water      share of population within 2 km of radar-detected open water
    mndwi, ndmi         Sentinel-2 water and moisture indices, Cloud Score+ masked, from 2017
    *_gap               share of the district under masked (cloudy / unobserved) pixels,
                        so the model can down-weight poorly observed months

Heavy layers (dynworld, s1water, s1near, s2index) run at 100 m and can take hours for
11 years. Run them separately, e.g. --layers dynworld --years 2015-2017.
"""
import argparse
import calendar
import json
import os
import socket
import time

import ee

YEARS = range(2015, 2026)
OUT = "data/derived/gee"
SCALE = 1000  # metres; the native scale of MODIS, coarser layers are resampled


def month_range(y, m):
    start = ee.Date.fromYMD(y, m, 1)
    return start, start.advance(1, "month")


def worldpop(y):
    # WorldPop GP 100 m runs to 2020; later years use 2020.
    yy = min(y, 2020)
    return (ee.ImageCollection("WorldPop/GP/100m/pop")
            .filter(ee.Filter.eq("country", "GHA"))
            .filter(ee.Filter.eq("year", yy)).first().rename("pop"))


# Each function returns an image of one or more bands for (year, month), or None if the
# product has no data for that month.
def lst(y, m):
    s, e = month_range(y, m)
    c = ee.ImageCollection("MODIS/061/MOD11A2").filterDate(s, e)
    day = c.select("LST_Day_1km").mean().multiply(0.02).subtract(273.15).rename("lst_day")
    night = c.select("LST_Night_1km").mean().multiply(0.02).subtract(273.15).rename("lst_night")
    gap = day.mask().Not().unmask(1).rename("lst_gap")
    return day.addBands(night).addBands(gap)


def veg(y, m):
    s, e = month_range(y, m)
    img = ee.ImageCollection("MODIS/061/MOD13A3").filterDate(s, e).first()
    ndvi = img.select("NDVI").multiply(0.0001).rename("ndvi")
    evi = img.select("EVI").multiply(0.0001).rename("evi")
    gap = ndvi.mask().Not().unmask(1).rename("ndvi_gap")
    return ndvi.addBands(evi).addBands(gap)


def chirps(y, m):
    s, e = month_range(y, m)
    return ee.ImageCollection("UCSB-CHG/CHIRPS/DAILY").filterDate(s, e).sum().rename("rain_chirps")


def imerg(y, m):
    s, e = month_range(y, m)
    hours = calendar.monthrange(y, m)[1] * 24
    c = ee.ImageCollection("NASA/GPM_L3/IMERG_MONTHLY_V07").filterDate(s, e)
    if c.size().getInfo() == 0:      # the final run lags by months: late 2025 is not out yet
        print("  no image", "imerg", y, m)
        return None
    return c.first().select("precipitation").multiply(hours).rename("rain_imerg")


def smap(y, m):
    if (y, m) < (2015, 4):
        return None
    s, e = month_range(y, m)
    return (ee.ImageCollection("NASA/SMAP/SPL4SMGP/008").filterDate(s, e)
            .select("sm_surface").mean().rename("soil_moisture"))


def era5(y, m):
    s, e = month_range(y, m)
    img = ee.ImageCollection("ECMWF/ERA5_LAND/MONTHLY_AGGR").filterDate(s, e).first()
    t = img.select("temperature_2m").subtract(273.15)
    td = img.select("dewpoint_temperature_2m").subtract(273.15)
    # Magnus formula
    rh = (td.multiply(17.625).divide(td.add(243.04)).exp()
          .divide(t.multiply(17.625).divide(t.add(243.04)).exp()).multiply(100))
    rain = img.select("total_precipitation_sum").multiply(1000)
    return t.rename("t2m").addBands(rh.rename("rh")).addBands(rain.rename("rain_era5"))


def gsw(y, m):
    if y > 2021:
        return None
    img = (ee.ImageCollection("JRC/GSW1_4/MonthlyHistory")
           .filter(ee.Filter.eq("year", y)).filter(ee.Filter.eq("month", m)).first().select("water"))
    # 0 = no data, 1 = not water, 2 = water; unobserved pixels are masked out
    return img.eq(2).updateMask(img.gt(0)).rename("water_frac")


def viirs(y, m):
    s, e = month_range(y, m)
    return (ee.ImageCollection("NOAA/VIIRS/DNB/MONTHLY_V1/VCMSLCFG").filterDate(s, e).first()
            .select("avg_rad").rename("nightlights"))


DW_CLASSES = ["water", "trees", "grass", "flooded_vegetation", "crops", "shrub_and_scrub",
              "built", "bare", "snow_and_ice"]


def dynworld(y, m):
    # Dynamic World V1 (10 m, from each Sentinel-2 scene, mid-2015 on) -> ANNUAL CLASS SHARES
    # (returned for m == 1 only; written with m empty). Monthly composites were tested and
    # rejected (2026-10-28): Harmattan haze turned Accra and Tema ~75% "bare" in January 2016
    # (91% built in November), and rainy-season cloud left 85-98% of forest districts unobserved
    # in some months. Land use changes slowly, and the galamsey test (s6b) uses yearly change.
    # 1. Each scene is cloud-masked with Cloud Score+ (cs_cdf >= 0.6), matched by scene id;
    #    DW itself is not cloud-masked.
    # 2. Per pixel, the class with the highest MEAN probability over the year's clear scenes
    #    (Google's recommended composite). Averaging the soft probabilities over a whole
    #    district instead understates the dominant class (first test: Amansie West, a forest
    #    district, came out 7% trees), so the shares are of LABELS, not of probabilities.
    # 3. Share of each class among the district's observed pixels. snow_and_ice is kept only as a
    #    residual-cloud check (should be ~0 in Ghana). dw_gap = share with no clear scene.
    #    2015 covers Jul-Dec only (DW starts mid-2015).
    # flooded_vegetation is the closest proxy for breeding habitat; bare + water growth in the
    # forest belt tracks surface mining (Section 6b of DESIGN.md).
    if m != 1:
        return None
    s, e = ee.Date.fromYMD(y, 1, 1), ee.Date.fromYMD(y + 1, 1, 1)
    csp = ee.ImageCollection("GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED").filterDate(s, e)
    c = (ee.ImageCollection("GOOGLE/DYNAMICWORLD/V1").filterDate(s, e)
         .filterBounds(ee.Geometry.Rectangle([-3.4, 4.6, 1.3, 11.2]))  # Ghana
         .linkCollection(csp, ["cs_cdf"])
         .map(lambda i: i.select(DW_CLASSES).updateMask(i.select("cs_cdf").gte(0.6))))
    label = c.mean().toArray().arrayArgmax().arrayGet(0)
    shares = [label.eq(i).rename("dw_" + k) for i, k in enumerate(DW_CLASSES)]
    gap = label.mask().Not().unmask(1).rename("dw_gap")
    return ee.Image.cat(shares + [gap])


def s1_water_flag(y, m):
    # Sentinel-1 C-band radar sees through cloud. Open water is dark in VV: each scene is
    # speckle-filtered (50 m focal median) and thresholded at -18 dB; the monthly mean of
    # the flag is the share of passes on which a pixel was water. The threshold is a common
    # default and is checked against JRC GSW for 2015-2021 before use.
    s, e = month_range(y, m)
    c = (ee.ImageCollection("COPERNICUS/S1_GRD").filterDate(s, e)
         .filter(ee.Filter.eq("instrumentMode", "IW"))
         .filter(ee.Filter.listContains("transmitterReceiverPolarisation", "VV"))
         .select("VV"))
    if c.size().getInfo() == 0:
        return None
    return c.map(lambda i: i.focalMedian(50, "circle", "meters").lt(-18)).mean()


def s1_water(y, m):
    w = s1_water_flag(y, m)
    if w is None:
        return None
    return w.rename("s1_water_frac").addBands(w.mask().Not().unmask(1).rename("s1_gap"))


def s1_near_water(y, m):
    # Share of the population living within 2 km of open water (water on at least half of
    # the month's passes), since Anopheles typically fly 1-2 km from breeding sites.
    # Computed at 100 m so small dams and dugouts are not lost.
    w = s1_water_flag(y, m)
    if w is None:
        return None
    w = w.gte(0.5).unmask(0)
    near = w.focalMax(2000, "circle", "meters").rename("pop_near_water")
    return near


def s2_index(y, m):
    # Sentinel-2 surface reflectance with Cloud Score+ masking (keep cs >= 0.6), monthly
    # median. MNDWI (green vs SWIR) marks open water; NDMI (NIR vs SWIR) tracks vegetation
    # and soil moisture. The harmonised SR collection starts in 2017.
    if y < 2017:
        return None
    s, e = month_range(y, m)
    cs = ee.ImageCollection("GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED")
    c = (ee.ImageCollection("COPERNICUS/S2_SR_HARMONIZED").filterDate(s, e)
         .linkCollection(cs, ["cs"])
         .map(lambda i: i.updateMask(i.select("cs").gte(0.6))))
    med = c.median()
    mndwi = med.normalizedDifference(["B3", "B11"]).rename("mndwi")
    ndmi = med.normalizedDifference(["B8", "B11"]).rename("ndmi")
    gap = mndwi.mask().Not().unmask(1).rename("s2_gap")
    return mndwi.addBands(ndmi).addBands(gap)


# layer -> (function, weighting, scale in metres)
#   "pop"  population-weighted mean: what people living in the district experience
#   "area" plain mean over the district's area: land cover and water shares, where
#          population weighting would wrongly drop pixels nobody lives on
ANNUAL = {"dynworld"}   # layers with one value per year (column m left empty)
LAYERS = {
    "lst": (lst, "pop", SCALE), "veg": (veg, "pop", SCALE), "chirps": (chirps, "pop", SCALE),
    "imerg": (imerg, "pop", SCALE), "smap": (smap, "pop", SCALE), "era5": (era5, "pop", SCALE),
    "viirs": (viirs, "pop", SCALE),
    "gsw": (gsw, "area", 100), "dynworld": (dynworld, "area", 100),
    "s1water": (s1_water, "area", 100), "s2index": (s2_index, "area", 100),
    "s1near": (s1_near_water, "pop", 100),
}


def extract(fc, layer, fn, weight, scale, y):
    path = os.path.join(OUT, f"{layer}_{y}.csv")
    if os.path.exists(path):
        print("skip", path)
        return
    pop = worldpop(y)
    rows = []
    for m in range(1, 13):
        img = fn(y, m)
        if img is None:
            continue
        if weight == "area":
            res = img.reduceRegions(collection=fc, reducer=ee.Reducer.mean(), scale=scale, tileScale=8)
            names = img.bandNames().getInfo()
            for attempt in range(5):
                try:
                    feats = res.getInfo()["features"]
                    break
                except (ee.EEException, OSError) as err:  # OSError includes request timeouts
                    print("  retry", layer, y, m, err)
                    time.sleep(10 * (attempt + 1))
            else:
                raise RuntimeError(f"failed {layer} {y}-{m}")
            for f in feats:
                p = f["properties"]
                # one band -> property "mean"; several bands -> one property per band name
                for b in names:
                    rows.append((p["unit"], y, "" if layer in ANNUAL else m, b,
                                 p.get("mean") if len(names) == 1 else p.get(b)))
            print(layer, y, m)
            continue
        bands = img.bandNames()
        reducer = ee.Reducer.mean().splitWeights()
        for b in bands.getInfo():
            src = img.select(b).addBands(pop)
            res = src.reduceRegions(collection=fc, reducer=reducer, scale=scale, tileScale=8)
            for attempt in range(5):
                try:
                    feats = res.getInfo()["features"]
                    break
                except (ee.EEException, OSError) as err:  # OSError includes request timeouts
                    print("  retry", layer, y, m, b, err)
                    time.sleep(10 * (attempt + 1))
            else:
                raise RuntimeError(f"failed {layer} {y}-{m} {b}")
            for f in feats:
                p = f["properties"]
                rows.append((p["unit"], y, m, b, p.get("mean")))
        print(layer, y, m)
    os.makedirs(OUT, exist_ok=True)
    with open(path, "w") as h:
        h.write("unit,year,m,variable,value\n")
        for r in rows:
            h.write(",".join("" if v is None else str(v) for v in r) + "\n")
    print("wrote", path, len(rows), "rows")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True, help="Google Cloud project registered for Earth Engine")
    ap.add_argument("--layers", default=",".join(LAYERS), help="comma-separated subset of: " + ",".join(LAYERS))
    ap.add_argument("--years", default=f"{YEARS.start}-{YEARS.stop - 1}")
    a = ap.parse_args()
    # time limit per request: a dropped connection otherwise hangs the run forever (seen twice)
    socket.setdefaulttimeout(300)
    import httplib2
    ee.Initialize(project=a.project, http_transport=httplib2.Http(timeout=300))
    with open("data/derived/units_simplified.geojson") as h:
        gj = json.load(h)
    fc = ee.FeatureCollection([ee.Feature(f["geometry"], {"unit": f["properties"]["unit"]})
                               for f in gj["features"]])
    y0, y1 = (int(v) for v in a.years.split("-"))
    for layer in a.layers.split(","):
        fn, weight, scale = LAYERS[layer]
        for y in range(y0, y1 + 1):
            extract(fc, layer, fn, weight, scale, y)


if __name__ == "__main__":
    main()
