# Satellite and climate covariates per district-month, ready for the model (DESIGN.md s3.2, s4).
# Usage: Rscript scripts/15_satellite_panel.R
# Input: data/derived/gee/<layer>_<year>.csv from 03_gee_extract.py (long: unit, year, m, variable, value)
#
# Cleaning (from the QA of 2026-10-29):
#   * ERA5-Land is empty for Krowor and Ledzokuku (coastal Accra, smaller than one land cell):
#     filled with the mean of their neighbouring districts in the same month.
#   * MODIS LST day/night gaps (cloud; 2.2% / 0.1%): linear interpolation in time within the
#     district, then the district's mean for that calendar month at the series ends.
#   * SMAP starts Apr 2015: Jan-Mar 2015 filled with the district's calendar-month mean.
#   * IMERG ends Sep 2025 (not yet released): kept with NA, used only as a sensitivity check.
#   * JRC GSW ends 2021: kept with NA, not used in the model; open water comes from Dynamic World.
#   * Dynamic World is ANNUAL. A real-time system only has last year's composite, so year y uses
#     the y-1 shares; 2015 (no earlier year) uses its own. 2015 is also the weakest year (43
#     districts with > 20% of the year without a clear view).
# Model inputs:
#   climate (distributed lags 0-3 months, built in 07_model.R): rain_chirps, lst_night, lst_day,
#     soil_moisture, ndvi, t2m, rh
#   environment: dw_built, dw_crops, dw_flooded_vegetation, dw_water, dw_bare (lagged one year),
#     log nightlights
# Output: data/derived/satellite_district_month.csv (one row per unit-year-month, 2015-2025)
suppressMessages({library(dplyr); library(tidyr); library(sf)}); sf_use_s2(FALSE)

files <- list.files("data/derived/gee", pattern = "^(chirps|dynworld|era5|lst|veg|imerg|smap|viirs|gsw)_\\d{4}\\.csv$",
                    full.names = TRUE)
files <- files[file.size(files) > 60]   # GSW 2022-25 files are header only (dataset ends 2021)
long <- bind_rows(lapply(files, read.csv))
monthly <- long |> filter(!is.na(m)) |> select(unit, year, m, variable, value) |>
  pivot_wider(names_from = variable, values_from = value)
annual <- long |> filter(is.na(m)) |> select(unit, year, variable, value) |>
  pivot_wider(names_from = variable, values_from = value)

cases <- read.csv("data/derived/cases_district_month.csv") |> select(unit, year, m)
p <- cases |> left_join(monthly, by = c("unit", "year", "m"))
stopifnot(nrow(p) == 247 * 132)

# ERA5 gaps: mean of the neighbours
u <- st_read("data/derived/units.gpkg", quiet = TRUE)
nb <- st_relate(u, u, pattern = "F***1****")
for (v in c("t2m", "rh", "rain_era5")) {
  for (un in unique(p$unit[is.na(p[[v]])])) {
    nbs <- u$unit[nb[[match(un, u$unit)]]]
    fill <- p |> filter(unit %in% nbs) |> group_by(year, m) |> summarise(f = mean(.data[[v]], na.rm = TRUE), .groups = "drop")
    i <- which(p$unit == un)
    p[[v]][i] <- fill$f[match(paste(p$year[i], p$m[i]), paste(fill$year, fill$m))]
    if (v == "t2m") cat("ERA5 filled for", un, "from", paste(nbs, collapse = ", "), "\n")
  }
}

# LST gaps: interpolate in time, then calendar-month mean at the ends
p <- p |> arrange(unit, year, m) |> group_by(unit) |>
  mutate(across(c(lst_day, lst_night), ~ {
    t <- seq_along(.x); ok <- !is.na(.x)
    if (sum(ok) > 1) approx(t[ok], .x[ok], t, rule = 1)$y else .x
  })) |>
  group_by(unit, m) |> mutate(across(c(lst_day, lst_night), ~ ifelse(is.na(.x), mean(.x, na.rm = TRUE), .x))) |>
  ungroup()
# SMAP starts Apr 2015: Jan-Mar 2015 (training lags only) get the district's calendar-month mean
p <- p |> group_by(unit, m) |>
  mutate(soil_moisture = ifelse(is.na(soil_moisture), mean(soil_moisture, na.rm = TRUE), soil_moisture)) |> ungroup()

# Dynamic World, lagged one year
dw <- annual |> transmute(unit, year = year + 1, dw_built, dw_crops, dw_flooded_vegetation, dw_water, dw_bare)
dw15 <- annual |> filter(year == 2015) |> transmute(unit, year, dw_built, dw_crops, dw_flooded_vegetation, dw_water, dw_bare)
p <- p |> left_join(bind_rows(dw15, dw |> filter(year <= 2025)), by = c("unit", "year")) |>
  mutate(log_nl = log1p(pmax(nightlights, 0)))

need <- c("rain_chirps", "lst_night", "lst_day", "soil_moisture", "ndvi", "t2m", "rh",
          "dw_built", "dw_crops", "dw_flooded_vegetation", "dw_water", "dw_bare", "log_nl")
miss <- sapply(p[need], function(x) sum(is.na(x)))
print(miss)
stopifnot(all(miss == 0))
out <- p |> select(unit, year, m, all_of(need), rain_imerg, water_frac, lst_gap, ndvi_gap)
write.csv(out, "data/derived/satellite_district_month.csv", row.names = FALSE)
cat("wrote data/derived/satellite_district_month.csv", nrow(out), "rows\n")
