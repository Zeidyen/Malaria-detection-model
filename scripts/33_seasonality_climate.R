# Is malaria seasonality explained by rainfall and the other environmental variables? (DESIGN.md s9 item 25)
# The model has a separate seasonal term (cyclic RW2 over calendar month, per zone), so the climate
# terms only describe departures from it. Three checks:
#  A. Descriptive: zone-average seasonal cycle of incidence and of each climate variable (2015-2025
#     monthly means); cross-correlation of the two cycles at lags 0-4 months, and the lag of the best
#     correlation. Cycles are only 12 points per zone, so this is descriptive.
#  B. Model decomposition, all data (Apr 2015 - Dec 2025), same data preparation, formula and priors
#     as 27_exposure_response.R. The seasonal term is fitted with no climate terms (M0), rain only (M1),
#     rain + soil moisture + NDVI (M2), all climate (M3) and all climate + environment (M4 = sat-all).
#     If climate drives the seasonal cycle, the zone seasonal term flattens as climate is added.
#     Amplitude = max - min of the posterior mean seasonal log rate ratio; share of amplitude taken over
#     by climate = 1 - amp(Mk)/amp(M0). Also the climate part of the linear predictor (posterior mean
#     coefficients x covariates), averaged by zone and calendar month = the seasonality climate implies.
#  C. Year-to-year timing: does the case season move when the rains move? Per district-year, the
#     seasonal centre (circular mean of calendar month weighted by the monthly value) of cases and of
#     rainfall; deviations from each district's own mean; regression of the case shift on the rain
#     shift (district-clustered SE), by zone. North zone has one rainy season; in the bimodal south the
#     centre is a cruder summary.
# Output: out/seasonality_climatology.csv, out/seasonality_xcorr.csv, out/seasonality_terms.csv,
#         out/seasonality_amplitude.csv, out/seasonality_timing.csv
suppressMessages({library(dplyr); library(tidyr); library(sf); library(INLA); library(dlnm);
                  library(sandwich); library(lmtest)}); sf_use_s2(FALSE)
ZONE <- c("Upper West" = "North", "Upper East" = "North", "North East" = "North",
  "Northern" = "North", "Savannah" = "North",
  "Ashanti" = "Forest", "Bono" = "Forest", "Bono East" = "Forest", "Ahafo" = "Forest",
  "Eastern" = "Forest", "Western North" = "Forest", "Oti" = "Forest",
  "Greater Accra" = "Coast", "Central" = "Coast", "Western" = "Coast", "Volta" = "Coast")
ZL <- c("North", "Forest", "Coast")

u <- st_read("data/derived/units.gpkg", quiet = TRUE)
nb <- st_relate(u, u, pattern = "F***1****")
G <- Matrix::sparseMatrix(i = rep(seq_along(nb), lengths(nb)), j = unlist(nb), x = 1,
                          dims = c(nrow(u), nrow(u)))
d <- read.csv("data/derived/cases_district_month.csv") |>
  mutate(zone = ZONE[Region], z = as.integer(factor(zone, levels = ZL)),
         sid = match(unit, u$unit), sid2 = sid, yid = year - min(year) + 1, yid2 = yid, y = conf_tot)
sp <- read.csv("data/derived/satellite_district_month.csv") |> arrange(unit, year, m)
CLIM <- c("rain_chirps", "lst_day", "lst_night", "soil_moisture", "ndvi", "t2m", "rh")
ENV <- c("dw_built", "dw_crops", "dw_flooded_vegetation", "dw_water", "dw_bare", "log_nl")

# ---- A. climatologies and cross-correlation -------------------------------------------------
dd <- d |> left_join(sp[, c("unit", "year", "m", CLIM)], by = c("unit", "year", "m"))
clim <- dd |> group_by(zone, m) |>
  summarise(inc_per_1000 = 1000 * sum(conf_tot, na.rm = TRUE) / sum(pop_tot[!is.na(conf_tot)]),
            across(all_of(CLIM), ~ mean(.x, na.rm = TRUE)), .groups = "drop") |>
  mutate(zone = factor(zone, ZL)) |> arrange(zone, m)
write.csv(clim, "out/seasonality_climatology.csv", row.names = FALSE)
xc <- list()
for (zn in ZL) for (v in CLIM) {
  cz <- clim |> filter(zone == zn)
  for (L in 0:4) {               # climate L months BEFORE cases (cyclic)
    xv <- cz[[v]][((cz$m - 1 - L) %% 12) + 1]
    xc[[length(xc) + 1]] <- data.frame(zone = zn, variable = v, lag = L, r = cor(log(cz$inc_per_1000), xv))
  }
}
xc <- bind_rows(xc)
write.csv(xc, "out/seasonality_xcorr.csv", row.names = FALSE)
cat("A. Correlation of the zone seasonal cycle of log incidence with each variable's cycle; best lag:\n")
print(xc |> group_by(zone, variable) |> slice_max(abs(r), n = 1) |> ungroup() |>
        mutate(r = round(r, 2)) |> pivot_wider(id_cols = variable, names_from = zone, values_from = c(r, lag)) |>
        as.data.frame(), row.names = FALSE)

# ---- B. seasonal term with and without climate ------------------------------------------------
X <- sp[, c("unit", "year", "m")]
for (v in CLIM) {
  cb <- crossbasis(as.numeric(scale(sp[[v]])), lag = 3, argvar = list(fun = "ns", df = 2),
                   arglag = list(fun = "ns", df = 2), group = sp$unit)
  mm <- unclass(cb)[, seq_len(ncol(cb)), drop = FALSE]
  colnames(mm) <- paste0("cb_", v, "_", seq_len(ncol(mm)))
  X <- cbind(X, mm)
}
for (v in ENV) X[[paste0("env_", v)]] <- as.numeric(scale(sp[[v]]))
allcols <- setdiff(names(X), c("unit", "year", "m"))
d <- left_join(d, X, by = c("unit", "year", "m"))
nolag <- !complete.cases(d[allcols])
d$y[nolag] <- NA; d[nolag, allcols] <- 0
cbs <- function(vs) unlist(lapply(vs, function(v) paste0("cb_", v, "_", 1:4)))
SPECS <- list(M0_none = character(0), M1_rain = cbs("rain_chirps"),
              M2_rain_soil_ndvi = cbs(c("rain_chirps", "soil_moisture", "ndvi")),
              M3_all_climate = cbs(CLIM), M4_climate_env = c(cbs(CLIM), paste0("env_", ENV)))
pc_prec <- list(prec = list(prior = "pc.prec", param = c(1, 0.01)))
base <- paste("y ~ 1 + offset(log(pop_tot)) +",
  "f(m, model = 'rw2', cyclic = TRUE, group = z, control.group = list(model = 'iid'), hyper = pc_prec, scale.model = TRUE) +",
  "f(sid, model = 'bym2', graph = G, scale.model = TRUE, hyper = list(prec = list(prior = 'pc.prec', param = c(1, 0.01)), phi = list(prior = 'pc', param = c(0.5, 0.5)))) +",
  "f(yid, model = 'iid', hyper = pc_prec) +",
  "f(yid2, model = 'ar1', replicate = sid2, hyper = list(prec = list(prior = 'pc.prec', param = c(1, 0.01)), rho = list(prior = 'pc.cor1', param = c(0.7, 0.7))))")
terms <- list(); climpart <- list()
for (nm in names(SPECS)) {
  cols <- SPECS[[nm]]
  f <- as.formula(paste(base, if (length(cols)) paste("+", paste(cols, collapse = " + ")) else ""))
  t0 <- Sys.time()
  fit <- inla(f, family = "nbinomial", data = d,
              control.fixed = list(mean = 0, prec = 1, mean.intercept = 0, prec.intercept = 0.001),
              control.compute = list(dic = TRUE), num.threads = "4:1", verbose = FALSE)
  cat(nm, "fitted in", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min, DIC",
      round(fit$dic$dic), "\n")
  r <- fit$summary.random$m
  terms[[nm]] <- data.frame(model = nm, zone = rep(ZL, each = 12), m = rep(1:12, 3),
                            est = r$mean, lo = r$`0.025quant`, hi = r$`0.975quant`, dic = fit$dic$dic)
  if (length(cols)) {
    lp <- as.matrix(d[, cols]) %*% fit$summary.fixed[cols, "mean"]
    climpart[[nm]] <- data.frame(model = nm, zone = d$zone, m = d$m, lp = lp[, 1])[!nolag, ] |>
      group_by(model, zone, m) |> summarise(clim_lp = mean(lp), .groups = "drop") |>
      group_by(model, zone) |> mutate(clim_lp = clim_lp - mean(clim_lp)) |> ungroup()
  }
}
T <- bind_rows(terms) |> left_join(bind_rows(climpart), by = c("model", "zone", "m"))
write.csv(T, "out/seasonality_terms.csv", row.names = FALSE)
amp <- T |> group_by(model, zone) |>
  summarise(season_amp = max(est) - min(est), peak_m = m[which.max(est)],
            clim_amp = if (all(is.na(clim_lp))) NA else max(clim_lp) - min(clim_lp),
            clim_peak_m = if (all(is.na(clim_lp))) NA else m[which.max(clim_lp)],
            r_season_clim = if (all(is.na(clim_lp))) NA else cor(est, clim_lp), dic = first(dic),
            .groups = "drop") |>
  group_by(zone) |> mutate(share_taken_by_climate = 1 - season_amp / season_amp[model == "M0_none"],
                           ratio_peak_to_trough = exp(season_amp)) |> ungroup()
write.csv(amp, "out/seasonality_amplitude.csv", row.names = FALSE)
cat("\nB. Zone seasonal term (log rate ratio, max - min) with and without climate terms:\n")
print(amp |> mutate(across(where(is.numeric), ~ round(.x, 3))) |> as.data.frame(), row.names = FALSE)

# ---- C. year-to-year timing -------------------------------------------------------------------
centre <- function(m, w) {         # circular weighted mean month, 1-12
  a <- 2 * pi * (m - 1) / 12
  ((atan2(sum(w * sin(a)), sum(w * cos(a))) %% (2 * pi)) * 12 / (2 * pi)) + 1
}
cdiff <- function(x, y) ((x - y + 6) %% 12) - 6     # signed circular difference, months
ty <- dd |> filter(!is.na(conf_tot), !is.na(rain_chirps)) |> group_by(unit, zone, year) |>
  filter(n() == 12) |>
  summarise(case_c = centre(m, conf_tot), rain_c = centre(m, rain_chirps), ndvi_c = centre(m, ndvi),
            rain_tot = sum(rain_chirps), cases = sum(conf_tot), .groups = "drop") |>
  group_by(unit) |>
  mutate(case_dev = cdiff(case_c, centre(case_c %% 12, rep(1, n()))),
         rain_dev = cdiff(rain_c, centre(rain_c %% 12, rep(1, n()))),
         ndvi_dev = cdiff(ndvi_c, centre(ndvi_c %% 12, rep(1, n())))) |> ungroup()
out <- list()
for (zn in ZL) for (v in c("rain_dev", "ndvi_dev")) {
  dz <- ty |> filter(zone == zn)
  ft <- lm(as.formula(paste("case_dev ~", v, "+ factor(year)")), data = dz)
  ct <- coeftest(ft, vcov = vcovCL(ft, cluster = ~unit))[v, ]
  ft0 <- lm(as.formula(paste("case_dev ~", v)), data = dz)
  ct0 <- coeftest(ft0, vcov = vcovCL(ft0, cluster = ~unit))[v, ]
  out[[length(out) + 1]] <- data.frame(zone = zn, predictor = v, district_years = nrow(dz),
    sd_case_shift = sd(dz$case_dev), sd_x_shift = sd(dz[[v]]),
    slope = ct0[1], lo = ct0[1] - 1.96 * ct0[2], hi = ct0[1] + 1.96 * ct0[2], p = ct0[4],
    slope_within_year = ct[1], lo_wy = ct[1] - 1.96 * ct[2], hi_wy = ct[1] + 1.96 * ct[2], p_wy = ct[4])
}
C <- bind_rows(out)
write.csv(C, "out/seasonality_timing.csv", row.names = FALSE)
cat("\nC. Shift of the case season (months) per month shift of the rain / NDVI season, district-years:\n")
print(C |> mutate(across(where(is.numeric), ~ signif(.x, 3))) |> as.data.frame(), row.names = FALSE)
cat("\nZone-year centres (month; 1 = Jan):\n")
print(ty |> group_by(zone, year) |> summarise(case_c = round(centre(case_c, rep(1, n())), 2),
      rain_c = round(centre(rain_c, rep(1, n())), 2), .groups = "drop") |>
      pivot_wider(names_from = zone, values_from = c(case_c, rain_c)) |> as.data.frame(), row.names = FALSE)
