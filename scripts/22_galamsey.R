# Pre-specified secondary analysis: surface mining (galamsey) and malaria (DESIGN.md s6b, s9 item 15).
# Usage: Rscript scripts/22_galamsey.R [MODEL=sat-all]
#
# Forest belt = districts of Ashanti, Western, Western North, Eastern and Central (as pre-specified).
# Exposure, defined without looking at malaria (as pre-specified): Dynamic World annual cloud-masked
# label shares; MINING districts = top quartile of the 2016 -> 2024 increase in the bare-ground share,
# within the forest belt. 2015 is not used (DW starts mid-2015; weakest year). DW drifts between
# years, so every model has year effects and compares forest-belt districts with each other.
# bw = bare + water share, the year BEFORE the outcome year (what a real-time system would have).
#
# Test 1 (pre-specified): district-year residual excess, log(sum observed / sum expected), from the
#   final model, 2018-2025, on bw and bw x mining, with district and year effects.
#   Caveat: the model's district x year AR1 learns the current year's level from earlier months, so
#   a SLOW rise is absorbed into the expected cases; this test is weak against gradual effects.
# Test 2 (pre-specified, ADAPTED): the plan compared flags before vs after 2016, but flags exist only
#   from 2018. Instead: months flagged per district-year, mining x late period (2022-25 vs 2018-21),
#   Poisson with district and year effects (difference in differences).
# Additional, NOT pre-specified (reported as such): log annual incidence 2016-2025 on bw (and on
#   Sentinel-1 radar water share, available through cloud) with district and year effects; and a
#   differential linear trend in mining districts.
# Standard errors clustered by district (sandwich::vcovCL).
# Output: out/galamsey_exposure.csv, out/galamsey_results.csv
suppressMessages({library(dplyr); library(tidyr); library(sandwich); library(lmtest)})
source("scripts/lib_preds.R")
MODEL <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "sat-all"
FOREST <- c("Ashanti", "Western", "Western North", "Eastern", "Central")

cases <- read.csv("data/derived/cases_district_month.csv")
reg <- cases |> distinct(unit, Region, District)
dw <- bind_rows(lapply(2016:2025, function(y) read.csv(sprintf("data/derived/gee/dynworld_%d.csv", y)))) |>
  filter(variable %in% c("dw_bare", "dw_water")) |> select(unit, year, variable, value) |>
  pivot_wider(names_from = variable, values_from = value) |>
  mutate(bw = dw_bare + dw_water) |> inner_join(reg, by = "unit") |> filter(Region %in% FOREST)

ex <- dw |> filter(year %in% c(2016, 2024)) |> select(unit, Region, District, year, dw_bare) |>
  pivot_wider(names_from = year, values_from = dw_bare, names_prefix = "bare_") |>
  mutate(d_bare = bare_2024 - bare_2016)
q75 <- quantile(ex$d_bare, 0.75)
ex <- ex |> mutate(mining = as.integer(d_bare >= q75)) |> arrange(desc(d_bare))
write.csv(ex, "out/galamsey_exposure.csv", row.names = FALSE)
cat(sprintf("Forest-belt districts: %d; mining (top quartile of bare-ground increase 2016-24, >= %.1f points): %d\n",
            nrow(ex), 100 * q75, sum(ex$mining)))
print(ex |> filter(mining == 1) |> transmute(Region, District, bare_2016 = round(100 * bare_2016, 1),
                                             bare_2024 = round(100 * bare_2024, 1), d_bare = round(100 * d_bare, 1)) |>
        as.data.frame(), row.names = FALSE)

# Sentinel-1 radar water share, annual mean of monthly values
s1 <- bind_rows(lapply(2016:2025, function(y) read.csv(sprintf("data/derived/gee/s1water_%d.csv", y)))) |>
  filter(variable == "s1_water_frac") |> group_by(unit, year) |> summarise(s1w = mean(value, na.rm = TRUE), .groups = "drop")

# district-year panel: exposure from the previous year
yr <- cases |> filter(Region %in% FOREST) |> group_by(unit, year) |>
  summarise(conf = sum(conf_tot), pop = mean(pop_tot), .groups = "drop") |>
  left_join(dw |> transmute(unit, year = year + 1, bw_lag = 100 * bw), by = c("unit", "year")) |>
  left_join(s1 |> transmute(unit, year = year + 1, s1w_lag = 100 * s1w), by = c("unit", "year")) |>
  left_join(ex |> select(unit, mining), by = "unit") |>
  mutate(log_inc = log(conf / pop * 1000))
p <- load_preds(MODEL) |> filter(unit %in% ex$unit)
res <- p |> group_by(unit, year) |>
  summarise(resid = log(sum(conf_tot) / sum(pred_med_adj)), months_flagged = sum(flag95_adj), .groups = "drop")
yr <- yr |> left_join(res, by = c("unit", "year"))

est <- function(fit, term, label, scale = "") {
  ct <- coeftest(fit, vcov = vcovCL(fit, cluster = ~unit))
  i <- which(rownames(ct) == term)
  data.frame(analysis = label, term = term, estimate = ct[i, 1], se = ct[i, 2], p = ct[i, 4],
             n = nobs(fit), scale = scale)
}
out <- list()
# Test 1: residual excess on bw, and its extra slope in mining districts
d1 <- yr |> filter(year >= 2018, !is.na(bw_lag))
f1 <- lm(resid ~ bw_lag + bw_lag:mining + factor(unit) + factor(year), data = d1)
out[[1]] <- est(f1, "bw_lag", "T1 residual excess ~ bare+water (prev. year), all forest belt", "log ratio per point")
out[[2]] <- est(f1, "bw_lag:mining", "T1 extra slope in mining districts", "log ratio per point")
# Test 2 (adapted): months flagged, mining x late period
d2 <- yr |> filter(year >= 2018) |> mutate(late = as.integer(year >= 2022))
f2 <- glm(months_flagged ~ mining:late + factor(unit) + factor(year), family = poisson, data = d2)
out[[3]] <- est(f2, "mining:late", "T2 (adapted) flags, mining x 2022-25 vs 2018-21", "log rate ratio")
# Additional (not pre-specified)
d3 <- yr |> filter(!is.na(bw_lag))
f3 <- lm(log_inc ~ bw_lag + factor(unit) + factor(year), data = d3)
out[[4]] <- est(f3, "bw_lag", "ADD log incidence ~ bare+water (prev. year), 2017-25", "log per point")
f4 <- lm(log_inc ~ s1w_lag + factor(unit) + factor(year), data = yr |> filter(!is.na(s1w_lag)))
out[[5]] <- est(f4, "s1w_lag", "ADD log incidence ~ Sentinel-1 water (prev. year), 2017-25", "log per point")
d5 <- yr |> mutate(t = year - 2020)
f5 <- lm(log_inc ~ mining:t + factor(unit) + factor(year), data = d5)
out[[6]] <- est(f5, "mining:t", "ADD differential incidence trend, mining districts, 2015-25", "log per year")
# Sensitivity (added after seeing the exposure distribution, before reading the outcome tests):
# the bare-ground change is zero-inflated, so the pre-specified top quartile reaches down to
# districts with ~0 change. Stricter definition: >= 0.5 percentage points of new bare ground.
# Rainfall control: wet district-years raise both open water and malaria.
rain <- read.csv("data/derived/satellite_district_month.csv") |> group_by(unit, year) |>
  summarise(rain_m = sum(rain_chirps) / 1000, .groups = "drop")      # metres per year
yr <- yr |> left_join(rain, by = c("unit", "year")) |>
  mutate(mining05 = as.integer(unit %in% ex$unit[ex$d_bare >= 0.005]))
cat("Stricter mining definition (>= 0.5 points):", sum(ex$d_bare >= 0.005), "districts\n")
f6 <- lm(log_inc ~ bw_lag + rain_m + factor(unit) + factor(year), data = yr |> filter(!is.na(bw_lag)))
out[[7]] <- est(f6, "bw_lag", "SENS log incidence ~ bare+water, + same-year rainfall", "log per point")
f7 <- lm(log_inc ~ s1w_lag + rain_m + factor(unit) + factor(year), data = yr |> filter(!is.na(s1w_lag)))
out[[8]] <- est(f7, "s1w_lag", "SENS log incidence ~ Sentinel-1 water, + same-year rainfall", "log per point")
f8 <- lm(resid ~ bw_lag + bw_lag:mining05 + factor(unit) + factor(year), data = yr |> filter(year >= 2018, !is.na(bw_lag)))
out[[9]] <- est(f8, "bw_lag:mining05", "SENS T1 extra slope, mining >= 0.5 points", "log ratio per point")
f9 <- lm(log_inc ~ mining05:t + factor(unit) + factor(year), data = yr |> mutate(t = year - 2020))
out[[10]] <- est(f9, "mining05:t", "SENS differential incidence trend, mining >= 0.5 points", "log per year")
R <- bind_rows(out)
R$ratio <- exp(R$estimate); R$lo <- exp(R$estimate - 1.96 * R$se); R$hi <- exp(R$estimate + 1.96 * R$se)
write.csv(R, "out/galamsey_results.csv", row.names = FALSE)
cat("\nResults (ratio = exp(estimate); 95% CI from district-clustered SE):\n")
print(R |> transmute(analysis, ratio = round(ratio, 3), lo = round(lo, 3), hi = round(hi, 3), p = signif(p, 2), n) ,
      row.names = FALSE)

# descriptive: incidence by group and year
cat("\nIncidence per 1,000 per year, forest belt (mining = stricter definition, >= 0.5 points):\n")
print(yr |> group_by(year, group = ifelse(mining05 == 1, "mining", "other")) |>
        summarise(inc = sum(conf) / sum(pop) * 1000, .groups = "drop") |>
        pivot_wider(names_from = group, values_from = inc) |> mutate(ratio = mining / other) |>
        mutate(across(where(is.numeric), ~ round(.x, 2))) |> as.data.frame(), row.names = FALSE)
