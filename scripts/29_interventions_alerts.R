# Interventions and alerts (DESIGN.md s9 item 24). Interventions are NOT in the expected-cases model
# (they did not improve prediction, s9 item 7, and an intervention failure should show up as an
# upsurge, not be explained away). Here the final system's alerts are set against the intervention
# calendar instead. Exploratory and descriptive: intervention data are mostly region-year.
# Usage: Rscript scripts/29_interventions_alerts.R [MODEL=sat-all]
#
# A. IRS insecticide switch (Coleman et al. 2026, PLOS Glob Public Health, Table 1 transcribed to
#    data/derived/irs_insecticide_cole2026.csv). In 22 northern IRS districts, spraying switched from
#    the organophosphate Actellic to neonicotinoids (SumiShield, Fludora Fusion) in 2018-2020, and the
#    paper estimates incidence 26% above its counterfactual afterwards (IRR 1.26, 1.07-2.08).
#    Did the system flag these districts after the switch? Event year = first neonicotinoid year.
#    Compared with the other North-zone districts in the same calendar years (difference in
#    differences): alerts per district-year ~ switch window + district + year effects, Poisson,
#    district-clustered SE. Switch window = event years 0 and 1. Also observed / expected (zone-
#    adjusted and raw) by event year. NB: our alerts start in 2018, so 2018 switchers have no
#    pre-switch year, and the AR1 absorbs a lasting step within about a year.
# B. Net campaigns: alerts per district-year by years since the region's last mass campaign
#    (0, 1, 2, 3+; coded as in 07_model.R A6), Poisson with year effects, district-clustered SE.
#    Campaigns are national waves, so campaign age and calendar year are largely collinear; the
#    contrast comes from regions and districts skipped in a round (IRS districts, urban centres).
# C. SMC: alert rate in SMC districts during SMC months (Jul-Oct, as coded in 07 A4) vs other months,
#    relative to the same months in non-SMC districts (interaction, Poisson with month and year
#    effects). Excess alerts in SMC months would point to delivery gaps; SMC-period seasonality is
#    already in the zone season term, so no excess is the expected result.
# Output: out/interventions_alerts.csv (tables A-C), out/irs_switch_by_event_year.csv
suppressMessages({library(dplyr); library(tidyr); library(sandwich); library(lmtest)})
source("scripts/lib_preds.R")
MODEL <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "sat-all"
NORTH <- c("Upper West", "Upper East", "North East", "Northern", "Savannah")

P <- load_preds(MODEL)
al <- read.csv(sprintf("out/alerts_%s_2018_2025.csv", MODEL))[, c("unit", "year", "m", "tier3")]
P <- P |> left_join(al, by = c("unit", "year", "m")) |>
  mutate(alert = as.integer(flag95_adj), trans = as.integer(!is.na(tier3) & tier3 == "transmission"))
dy <- P |> group_by(unit, Region, zone, year) |>
  summarise(alerts = sum(alert), trans = sum(trans), obs = sum(conf_tot), exp_adj = sum(pred_med_adj),
            exp_raw = sum(pred_med), .groups = "drop")

est <- function(fit, term, label) {
  ct <- coeftest(fit, vcov = vcovCL(fit, cluster = ~unit))
  i <- which(rownames(ct) == term)
  data.frame(analysis = label, term = term, rr = exp(ct[i, 1]), lo = exp(ct[i, 1] - 1.96 * ct[i, 2]),
             hi = exp(ct[i, 1] + 1.96 * ct[i, 2]), p = ct[i, 4], n = nobs(fit))
}
out <- list()

# ---- A. IRS insecticide switch ---------------------------------------------------------------
irs <- read.csv("data/derived/irs_insecticide_cole2026.csv")
stopifnot(all(irs$unit %in% dy$unit))
a <- dy |> filter(zone == "North") |>
  left_join(irs |> select(unit, neonic_first), by = "unit") |>
  mutate(irs22 = !is.na(neonic_first), ev = year - neonic_first,
         window = as.integer(irs22 & ev %in% 0:1))
ev_tab <- a |> filter(irs22) |> mutate(ev = ifelse(ev >= 4, "4+", as.character(ev))) |>
  group_by(ev) |>
  summarise(district_years = n(), alerts_per_dy = mean(alerts), trans_per_dy = mean(trans),
            share_with_alert = mean(alerts > 0), obs_exp_adj = sum(obs) / sum(exp_adj),
            obs_exp_raw = sum(obs) / sum(exp_raw), .groups = "drop")
ref <- a |> filter(!irs22) |> summarise(ev = "other North districts, 2018-25", district_years = n(),
  alerts_per_dy = mean(alerts), trans_per_dy = mean(trans), share_with_alert = mean(alerts > 0),
  obs_exp_adj = sum(obs) / sum(exp_adj), obs_exp_raw = sum(obs) / sum(exp_raw))
ev_tab <- bind_rows(ev_tab, ref)
write.csv(ev_tab, "out/irs_switch_by_event_year.csv", row.names = FALSE)
cat("A. 22 IRS districts by year relative to the first neonicotinoid year (0 = switch year):\n")
print(ev_tab |> mutate(across(where(is.numeric), ~ round(.x, 3))) |> as.data.frame(), row.names = FALSE)
fa <- glm(alerts ~ window + factor(unit) + factor(year), family = poisson, data = a)
out[[1]] <- est(fa, "window", "A alerts, IRS districts in switch year and year after vs other North district-years")
ft <- glm(trans ~ window + factor(unit) + factor(year), family = poisson, data = a)
out[[2]] <- est(ft, "window", "A transmission alerts, same contrast")
# per-district detail in the switch window
det <- a |> filter(irs22, ev %in% 0:1) |> group_by(unit, Region, neonic_first) |>
  summarise(alerts = sum(alerts), trans = sum(trans), obs_exp_raw = sum(obs) / sum(exp_raw), .groups = "drop") |>
  arrange(desc(alerts))
cat("\nSwitch year and year after, per district:\n")
print(det |> mutate(obs_exp_raw = round(obs_exp_raw, 2)) |> as.data.frame(), row.names = FALSE)

# ---- B. net campaign age ---------------------------------------------------------------------
iv <- read.csv("data/derived/interventions_district_year.csv")
camp <- iv |> distinct(Region, year, itn_campaign_region) |>
  mutate(c = !is.na(itn_campaign_region) & itn_campaign_region == 1) |> arrange(Region, year) |>
  group_by(Region) |> mutate(last = cummax(ifelse(c, year, -Inf))) |> ungroup() |>
  mutate(itn_age = pmin(year - last, 3), itn_age = ifelse(is.finite(itn_age), itn_age, 3)) |>
  select(Region, year, itn_age)
b <- dy |> left_join(camp, by = c("Region", "year")) |> mutate(itn_age = factor(itn_age, levels = 0:3))
cat("\nB. Alerts per district-year by years since the region's last net campaign:\n")
print(b |> group_by(itn_age) |> summarise(district_years = n(), alerts = mean(alerts), trans = mean(trans),
                                          .groups = "drop") |> as.data.frame(), row.names = FALSE)
cat("district-years by campaign age and year:\n"); print(table(b$year, b$itn_age))
fb <- glm(trans ~ itn_age + factor(year), family = poisson, data = b)
for (k in 1:3) out[[length(out) + 1]] <- est(fb, paste0("itn_age", k),
  sprintf("B transmission alerts, %s years since campaign vs campaign year (year effects)", c("1", "2", "3+")[k]))

# ---- C. SMC months ---------------------------------------------------------------------------
smc <- iv |> mutate(smc_x = case_when(!is.na(smc_alt) ~ as.numeric(smc_alt), Region %in% NORTH ~ 1,
                                      Region == "Bono East" ~ 0.4, Region == "Oti" ~ 1, TRUE ~ 0)) |>
  select(unit, year, smc_x)
cm <- P |> left_join(smc, by = c("unit", "year")) |>
  mutate(smc_dist = as.integer(smc_x >= 0.5), smc_month = as.integer(m %in% 7:10))
cat("\nC. Alert rate (% of district-months) by SMC district and SMC months (Jul-Oct):\n")
print(cm |> group_by(smc_dist, smc_month) |> summarise(dm = n(), alert_pct = 100 * mean(alert),
        trans_pct = 100 * mean(trans), .groups = "drop") |> as.data.frame(), row.names = FALSE)
fc <- glm(alert ~ smc_dist * smc_month + factor(m) + factor(year), family = poisson, data = cm)
out[[length(out) + 1]] <- est(fc, "smc_dist:smc_month", "C alerts, SMC districts in SMC months (interaction)")
fc2 <- glm(trans ~ smc_dist * smc_month + factor(m) + factor(year), family = poisson, data = cm)
out[[length(out) + 1]] <- est(fc2, "smc_dist:smc_month", "C transmission alerts, same interaction")

R <- bind_rows(out)
write.csv(R, "out/interventions_alerts.csv", row.names = FALSE)
cat("\nRate ratios (95% CI, district-clustered SE):\n")
print(R |> mutate(across(c(rr, lo, hi), ~ round(.x, 2)), p = signif(p, 2)) |> as.data.frame(), row.names = FALSE)
