# Expected-cases model with intervention terms, plus the two-tier alert (DESIGN.md s4-5, s9).
# Extends 05_baseline.R (which stays as the reference baseline). One rolling-origin step:
# fit on years before TARGET, predict every district-month of TARGET.
#
#   SPEC = "base": season (cyclic RW2 per zone) + BYM2 district + IID year + district trend
#   SPEC = "int" : base + SMC (active months) + IRS + years since ITN campaign + vaccine + COVID
#   SPEC = "sat" : as ar, plus satellite/climate covariates (data/derived/satellite_district_month.csv,
#                  15_satellite_panel.R). Groups chosen by the environment variable SAT (comma list,
#                  or "all"): rain (CHIRPS), lst (MODIS day + night), sm (SMAP soil moisture), ndvi,
#                  era5 (2 m temperature, humidity) = DLNM cross-basis per variable, lags 0-3 months
#                  (natural spline in the value, df 2, and in the lag, df 2: 4 columns); env =
#                  Dynamic World built/crops/flooded vegetation/water/bare (previous year) and log
#                  night lights, standardised, linear. Lag-0 values are usable in real time: they
#                  are published within days of the month's end, before the DHIMS2 cases are complete.
#                  Covariates are exogenous, so the bases are built once on the whole 2015-25 panel;
#                  only the outcome is restricted to the training months. Jan-Mar 2015 (incomplete
#                  lags) are left out of the fit. Output tag: sat-<groups>, e.g. sat-all, sat-rain.
#   SPEC = "ar"  : as base, but the linear district trend is replaced by a district x year AR1
#                  effect. A linear trend projects a temporary level shift (e.g. the 2019-21
#                  urban reporting jumps) forward for ever; the AR1 lets a district sit high for
#                  a few years and then reverts its forecast towards the district's usual level.
#
# Intervention coding (data/derived/interventions_district_year.csv, `smc_alt` = MAIN SMC coding,
# decided 2026-10-27). Gaps are filled by explicit assumptions:
#   A1 SMC NA in the five northern regions -> 1 (the programme ran continuously from its start
#      year; NA means the district was not named, not that SMC stopped).
#   A2 SMC NA in Bono East -> 0.4 (5 of 11 districts covered; only Sene East is named, so the
#      other 4 are spread over the 10 unnamed districts).
#   A3 SMC NA in Oti 2021 -> 1 (source is region-level only).
#   A4 SMC months from cycles: 2 -> Aug-Sep, 3 -> Jul-Sep, 4 or NA -> Jul-Oct, 5 -> Jun-Oct.
#   A5 IRS NA -> 0; IRS acts from the first spray month (default April) to December.
#   A6 ITN: years since the region's last mass campaign (0, 1, 2, 3+); region NA -> no campaign.
#   A7 Vaccine NA -> 0 (the NA cells are 2025 in never-covered regions).
#   A8 COVID: indicator for Apr-Dec 2020, used only when 2020 is in the training data.
# An intervention term is DROPPED when it does not vary in the training data (its coefficient
# would otherwise be the prior alone, times non-zero values in the target year). Fixed effects
# for interventions get N(0, 1) priors on the log scale.
#
# Alert, two tiers (DESIGN.md s9 item 6):
#   raw      : observed > upper 95% of the predictive draws
#   zone-adj : draws rescaled by the zone-month ratio obs/pred of the OTHER districts in the zone
#              (leave-one-out), so a zone-wide shift is not read as a local anomaly
#
# Monthly updating (optional 3rd argument MONTH): fit on every month up to MONTH - 1 of TARGET,
# and predict MONTH only. This is how the system would run in real time, since the district's
# earlier months of the current year are already reported. With the AR1 term it lets the
# district's current-year level be learned from those months instead of being guessed a year
# ahead.
#
# Usage: Rscript scripts/07_model.R TARGET SPEC [MONTH]
# Output: out/model_<SPEC>_<TARGET>_pred.csv, out/model_<SPEC>_<TARGET>_fixed.csv
#         with MONTH: out/monthly/model_<SPEC>_<TARGET>_<MM>_pred.csv (and _fixed.csv)
suppressMessages({library(dplyr); library(sf); library(INLA)}); sf_use_s2(FALSE)
args <- commandArgs(TRUE)
TARGET <- as.integer(args[1]); SPEC <- args[2]
MONTH <- if (length(args) > 2) as.integer(args[3]) else NA_integer_
SATG <- if (SPEC == "sat") strsplit(Sys.getenv("SAT", "all"), ",")[[1]] else character(0)
if (identical(SATG, "all")) { SATG <- c("rain", "lst", "sm", "ndvi", "era5", "env"); LAB <- "sat-all" } else LAB <- paste0("sat-", paste(SATG, collapse = "-"))
# SATLAG0=0: climate lags 1-3 only (nothing from the month being judged; real-time check). Tag -l13.
LAG0 <- Sys.getenv("SATLAG0", "1") != "0"
if (SPEC == "sat" && !LAG0) LAB <- paste0(LAB, "-l13")
if (SPEC != "sat") LAB <- SPEC
TAG <- if (is.na(MONTH)) sprintf("model_%s_%d", LAB, TARGET) else sprintf("monthly/model_%s_%d_%02d", LAB, TARGET, MONTH)
if (!is.na(MONTH)) dir.create("out/monthly", showWarnings = FALSE)
stopifnot(SPEC %in% c("base", "int", "ar", "sat"))
NSAMP <- 500
set.seed(20261027 + TARGET)

# Ghana's three broad ecological belts, by region (as in 05_baseline.R).
ZONE <- c("Upper West" = "North", "Upper East" = "North", "North East" = "North",
  "Northern" = "North", "Savannah" = "North",
  "Ashanti" = "Forest", "Bono" = "Forest", "Bono East" = "Forest", "Ahafo" = "Forest",
  "Eastern" = "Forest", "Western North" = "Forest", "Oti" = "Forest",
  "Greater Accra" = "Coast", "Central" = "Coast", "Western" = "Coast", "Volta" = "Coast")
NORTH <- c("Upper West", "Upper East", "North East", "Northern", "Savannah")

u <- st_read("data/derived/units.gpkg", quiet = TRUE)
nb <- st_relate(u, u, pattern = "F***1****")
G <- Matrix::sparseMatrix(i = rep(seq_along(nb), lengths(nb)), j = unlist(nb), x = 1,
                          dims = c(nrow(u), nrow(u)))

# ---- interventions ------------------------------------------------------------------------
iv <- read.csv("data/derived/interventions_district_year.csv") |>
  mutate(smc_x = case_when(!is.na(smc_alt) ~ as.numeric(smc_alt),
                           Region %in% NORTH ~ 1,                     # A1
                           Region == "Bono East" ~ 0.4,               # A2
                           Region == "Oti" ~ 1,                       # A3
                           TRUE ~ 0),
         cyc = ifelse(is.na(smc_alt_cycles) | smc_alt_cycles == 0, 4, smc_alt_cycles),
         smc_m0 = c(`2` = 8, `3` = 7, `4` = 7, `5` = 6)[as.character(cyc)],   # A4
         smc_m1 = c(`2` = 9, `3` = 9, `4` = 10, `5` = 10)[as.character(cyc)],
         irs_x = ifelse(is.na(irs), 0, irs),                          # A5
         irs_m0 = match(substr(irs_month, 1, 3), month.abb),
         irs_m0 = ifelse(is.na(irs_m0), 4, irs_m0),
         vac_x = ifelse(is.na(vaccine), 0, vaccine))                  # A7
# A6: years since the region's last campaign
camp <- iv |> distinct(Region, year, itn_campaign_region) |>
  mutate(c = !is.na(itn_campaign_region) & itn_campaign_region == 1) |> arrange(Region, year) |>
  group_by(Region) |> mutate(last = cummax(ifelse(c, year, -Inf))) |> ungroup() |>
  mutate(itn_age = pmin(year - last, 3), itn_age = ifelse(is.finite(itn_age), itn_age, 3)) |>
  select(Region, year, itn_age)
iv <- left_join(iv, camp, by = c("Region", "year"))

d <- read.csv("data/derived/cases_district_month.csv") |>
  filter(year < TARGET | (year == TARGET & (is.na(MONTH) | m <= MONTH))) |>
  left_join(select(iv, unit, year, smc_x, smc_m0, smc_m1, irs_x, irs_m0, vac_x, itn_age),
            by = c("unit", "year")) |>
  mutate(zone = ZONE[Region], z = as.integer(factor(zone, levels = c("North", "Forest", "Coast"))),
         sid = match(unit, u$unit), sid2 = sid, yid = year - min(year) + 1, yid2 = yid,
         tc = (year - TARGET) / 5,
         is_target = year == TARGET & (is.na(MONTH) | m == MONTH),
         y = ifelse(is_target, NA, conf_tot),
         smc_on = smc_x * (m >= smc_m0 & m <= smc_m1),
         irs_on = irs_x * (m >= irs_m0),
         itn0 = as.numeric(itn_age == 0), itn1 = as.numeric(itn_age == 1),
         itn2 = as.numeric(itn_age == 2),
         vac_on = vac_x,
         covid = as.numeric(year == 2020 & m >= 4))
stopifnot(!anyNA(d$zone), !anyNA(d$sid), !anyNA(d$smc_on), !anyNA(d$itn_age))

# ---- satellite covariates (SPEC sat) --------------------------------------------------------
satcols <- character(0)
if (SPEC == "sat") {
  sp <- read.csv("data/derived/satellite_district_month.csv") |> arrange(unit, year, m)
  CLIM <- list(rain = "rain_chirps", lst = c("lst_day", "lst_night"), sm = "soil_moisture",
               ndvi = "ndvi", era5 = c("t2m", "rh"))
  ENV <- c("dw_built", "dw_crops", "dw_flooded_vegetation", "dw_water", "dw_bare", "log_nl")
  X <- sp[, c("unit", "year", "m")]
  for (g in intersect(SATG, names(CLIM))) for (v in CLIM[[g]]) {
    x <- as.numeric(scale(sp[[v]]))
    cb <- dlnm::crossbasis(x, lag = if (LAG0) 3 else c(1, 3), argvar = list(fun = "ns", df = 2),
                           arglag = list(fun = "ns", df = 2), group = sp$unit)
    cb <- unclass(cb)[, seq_len(ncol(cb)), drop = FALSE]
    colnames(cb) <- paste0("cb_", v, "_", seq_len(ncol(cb)))
    X <- cbind(X, cb)
  }
  if ("env" %in% SATG) for (v in ENV) X[[paste0("env_", v)]] <- as.numeric(scale(sp[[v]]))
  satcols <- setdiff(names(X), c("unit", "year", "m"))
  d <- left_join(d, X, by = c("unit", "year", "m"))
  nolag <- !complete.cases(d[satcols])
  stopifnot(all(d$year[nolag] == 2015 & d$m[nolag] <= 3))
  d$y[nolag] <- NA; d[nolag, satcols] <- 0
  cat("satellite groups:", SATG, "|", length(satcols), "columns\n")
}

pc_prec <- list(prec = list(prior = "pc.prec", param = c(1, 0.01)))
f <- y ~ 1 + offset(log(pop_tot)) +
  f(m, model = "rw2", cyclic = TRUE, group = z, control.group = list(model = "iid"),
    hyper = pc_prec, scale.model = TRUE) +
  f(sid, model = "bym2", graph = G, scale.model = TRUE,
    hyper = list(prec = list(prior = "pc.prec", param = c(1, 0.01)),
                 phi = list(prior = "pc", param = c(0.5, 0.5)))) +
  f(yid, model = "iid", hyper = pc_prec) +
  f(yid2, model = "ar1", replicate = sid2,
    hyper = list(prec = list(prior = "pc.prec", param = c(1, 0.01)),
                 rho = list(prior = "pc.cor1", param = c(0.7, 0.7))))
if (!SPEC %in% c("ar", "sat")) f <- update(f, . ~ . - f(yid2, model = "ar1", replicate = sid2,
    hyper = list(prec = list(prior = "pc.prec", param = c(1, 0.01)),
                 rho = list(prior = "pc.cor1", param = c(0.7, 0.7)))) +
    f(sid2, tc, model = "iid", hyper = pc_prec))
used <- character(0)
if (SPEC == "sat") f <- update(f, as.formula(paste(". ~ . +", paste(satcols, collapse = " + "))))
if (SPEC == "int") {
  train <- d[!d$is_target, ]
  cand <- c("smc_on", "irs_on", "itn0", "itn1", "itn2", "vac_on", "covid")
  used <- cand[sapply(cand, function(v) length(unique(train[[v]])) > 1)]
  dropped <- setdiff(cand, used)
  if (length(dropped)) cat("dropped (no variation in training):", dropped, "\n")
  f <- update(f, as.formula(paste(". ~ . +", paste(used, collapse = " + "))))
}

# INLA_SAFE=1: fallback for fits where the default optimiser fails to converge (Jul 2021 and
# Jul 2023 in the monthly AR1 run): Gaussian approximation, hyperparameters at their mode (EB).
SAFE <- Sys.getenv("INLA_SAFE") == "1"
if (SAFE) cat("INLA_SAFE: strategy = gaussian, int.strategy = eb\n")
t0 <- Sys.time()
fit <- inla(f, family = "nbinomial", data = d,
            control.predictor = list(compute = TRUE, link = 1),
            control.fixed = list(mean = 0, prec = 1, mean.intercept = 0, prec.intercept = 0.001),
            control.compute = list(config = TRUE),
            control.inla = if (SAFE) list(strategy = "gaussian", int.strategy = "eb") else list(),
            num.threads = "4:1", verbose = FALSE)
cat("fit", TARGET, SPEC, "in", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")
fx <- fit$summary.fixed[, c("mean", "0.025quant", "0.975quant")]
fx$rate_ratio <- exp(fx$mean)
print(round(fx, 3))
write.csv(cbind(term = rownames(fx), fx), sprintf("out/%s_fixed.csv", TAG), row.names = FALSE)

# ---- predictive draws for the target year -----------------------------------------------
idx <- which(d$is_target)
s <- inla.posterior.sample(NSAMP, fit, num.threads = "4:1")
eta_rows <- grep("^Predictor:", rownames(s[[1]]$latent))[idx]
draw <- sapply(s, function(x) {
  size <- x$hyperpar[grep("size", names(x$hyperpar))]
  rnbinom(length(eta_rows), size = size, mu = exp(x$latent[eta_rows]))
})
obs <- d$conf_tot[idx]
med <- apply(draw, 1, median)

# zone-adjusted draws: leave-one-out zone-month ratio
key <- paste(d$zone[idx], d$m[idx])
tot_o <- tapply(obs, key, sum)[key]; tot_p <- tapply(med, key, sum)[key]
R_loo <- as.numeric((tot_o - obs) / (tot_p - med))
R_zone <- as.numeric(tot_o / tot_p)
draw_adj <- draw * R_loo

summ <- function(dr) {
  q <- t(apply(dr, 1, quantile, c(0.025, 0.5, 0.975)))
  crps <- sapply(seq_along(obs), function(i) {
    x <- dr[i, ]; mean(abs(x - obs[i])) - 0.5 * mean(abs(x - sample(x)))
  })
  list(q = q, crps = crps, pit = rowMeans(dr < obs) + 0.5 * rowMeans(dr == obs))
}
a <- summ(draw); b <- summ(draw_adj)
out <- d[idx, c("unit", "Region", "District", "zone", "year", "m", "pop_tot", "conf_tot")] |>
  mutate(pred_med = a$q[, 2], lo95 = a$q[, 1], hi95 = a$q[, 3], crps = a$crps, pit = a$pit,
         flag95 = conf_tot > hi95,
         R_zone = as.numeric(R_zone), R_loo = as.numeric(R_loo),
         pred_med_adj = b$q[, 2], lo95_adj = b$q[, 1], hi95_adj = b$q[, 3],
         crps_adj = b$crps, pit_adj = b$pit, flag95_adj = conf_tot > hi95_adj)
write.csv(out, sprintf("out/%s_pred.csv", TAG), row.names = FALSE)

cat(sprintf("\n%d %s: coverage95 raw %.3f adj %.3f | flagged raw %.3f adj %.3f | CRPS raw %.1f adj %.1f\n",
  TARGET, SPEC, mean(obs >= a$q[, 1] & obs <= a$q[, 3]), mean(obs >= b$q[, 1] & obs <= b$q[, 3]),
  mean(out$flag95), mean(out$flag95_adj), mean(a$crps), mean(b$crps)))
