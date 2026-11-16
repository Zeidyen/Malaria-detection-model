# Exposure-lag-response of the climate and satellite terms (DESIGN.md s9 item 23).
# The monthly fits (07_model.R) are for prediction; their spline coefficients cannot be read
# directly. Here the final model (SPEC sat, all groups, lags 0-3) is fitted ONCE on all data,
# Apr 2015 - Dec 2025, with the same data preparation, formula and priors as 07_model.R. Then:
#   * 2,000 joint posterior samples of the fixed effects -> posterior mean and covariance of each
#     variable's 4 cross-basis coefficients -> dlnm::crosspred (log link):
#       - cumulative rate ratio over lags 0-3, across the variable's P2.5-P97.5 range, centred at
#         its median;
#       - lag-specific rate ratio at the 10th and 90th percentiles vs the median.
#   * environment terms: rate ratio per SD (as fitted) and per natural unit.
# Interpretation: these are associations CONDITIONAL on zone seasonality, district (BYM2), year and
# district x year AR1 effects, i.e. of month-to-month departures from each district's usual
# seasonal pattern and level. Long-run differences between districts are absorbed by the district
# effects. Associations, not causal effects.
# Usage: Rscript scripts/27_exposure_response.R
# Output: out/exposure_response_cumulative.csv, out/exposure_response_lag.csv,
#         out/exposure_response_env.csv, out/exposure_response_fixed.csv
suppressMessages({library(dplyr); library(sf); library(INLA); library(dlnm)}); sf_use_s2(FALSE)
set.seed(20261031)
NSAMP <- 2000
ZONE <- c("Upper West" = "North", "Upper East" = "North", "North East" = "North",
  "Northern" = "North", "Savannah" = "North",
  "Ashanti" = "Forest", "Bono" = "Forest", "Bono East" = "Forest", "Ahafo" = "Forest",
  "Eastern" = "Forest", "Western North" = "Forest", "Oti" = "Forest",
  "Greater Accra" = "Coast", "Central" = "Coast", "Western" = "Coast", "Volta" = "Coast")

u <- st_read("data/derived/units.gpkg", quiet = TRUE)
nb <- st_relate(u, u, pattern = "F***1****")
G <- Matrix::sparseMatrix(i = rep(seq_along(nb), lengths(nb)), j = unlist(nb), x = 1,
                          dims = c(nrow(u), nrow(u)))
d <- read.csv("data/derived/cases_district_month.csv") |>
  mutate(zone = ZONE[Region], z = as.integer(factor(zone, levels = c("North", "Forest", "Coast"))),
         sid = match(unit, u$unit), sid2 = sid, yid = year - min(year) + 1, yid2 = yid, y = conf_tot)

sp <- read.csv("data/derived/satellite_district_month.csv") |> arrange(unit, year, m)
CLIM <- c("rain_chirps", "lst_day", "lst_night", "soil_moisture", "ndvi", "t2m", "rh")
ENV <- c("dw_built", "dw_crops", "dw_flooded_vegetation", "dw_water", "dw_bare", "log_nl")
X <- sp[, c("unit", "year", "m")]
CB <- list()                                    # crossbasis objects kept for crosspred
for (v in CLIM) {
  x <- as.numeric(scale(sp[[v]]))
  cb <- crossbasis(x, lag = 3, argvar = list(fun = "ns", df = 2), arglag = list(fun = "ns", df = 2),
                   group = sp$unit)
  CB[[v]] <- cb
  m <- unclass(cb)[, seq_len(ncol(cb)), drop = FALSE]
  colnames(m) <- paste0("cb_", v, "_", seq_len(ncol(m)))
  X <- cbind(X, m)
}
for (v in ENV) X[[paste0("env_", v)]] <- as.numeric(scale(sp[[v]]))
satcols <- setdiff(names(X), c("unit", "year", "m"))
d <- left_join(d, X, by = c("unit", "year", "m"))
nolag <- !complete.cases(d[satcols])
stopifnot(all(d$year[nolag] == 2015 & d$m[nolag] <= 3))
d$y[nolag] <- NA; d[nolag, satcols] <- 0

CACHE <- "out/exposure_response_samples.rds"   # posterior samples, so post-processing can be rerun
if (file.exists(CACHE)) B <- readRDS(CACHE) else {
pc_prec <- list(prec = list(prior = "pc.prec", param = c(1, 0.01)))
f <- as.formula(paste("y ~ 1 + offset(log(pop_tot)) +",
  "f(m, model = 'rw2', cyclic = TRUE, group = z, control.group = list(model = 'iid'), hyper = pc_prec, scale.model = TRUE) +",
  "f(sid, model = 'bym2', graph = G, scale.model = TRUE, hyper = list(prec = list(prior = 'pc.prec', param = c(1, 0.01)), phi = list(prior = 'pc', param = c(0.5, 0.5)))) +",
  "f(yid, model = 'iid', hyper = pc_prec) +",
  "f(yid2, model = 'ar1', replicate = sid2, hyper = list(prec = list(prior = 'pc.prec', param = c(1, 0.01)), rho = list(prior = 'pc.cor1', param = c(0.7, 0.7)))) +",
  paste(satcols, collapse = " + ")))
SAFE <- Sys.getenv("INLA_SAFE") == "1"
t0 <- Sys.time()
fit <- inla(f, family = "nbinomial", data = d,
            control.fixed = list(mean = 0, prec = 1, mean.intercept = 0, prec.intercept = 0.001),
            control.compute = list(config = TRUE),
            control.inla = if (SAFE) list(strategy = "gaussian", int.strategy = "eb") else list(),
            num.threads = "4:1", verbose = FALSE)
cat("fit in", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")
fx <- fit$summary.fixed[, c("mean", "sd", "0.025quant", "0.975quant")]
write.csv(cbind(term = rownames(fx), fx), "out/exposure_response_fixed.csv", row.names = FALSE)
print(round(fx, 3))

# joint posterior samples of the fixed effects
sel <- setNames(as.list(rep(1, length(satcols))), satcols)
s <- inla.posterior.sample(NSAMP, fit, selection = sel, num.threads = "4:1")
B <- t(sapply(s, function(x) x$latent[, 1]))                 # NSAMP x length(satcols)
colnames(B) <- sub(":1$", "", rownames(s[[1]]$latent))
stopifnot(all(satcols %in% colnames(B)))

saveRDS(B, CACHE)
}
cum <- list(); lagr <- list()
for (v in CLIM) {
  raw <- sp[[v]]; mu <- mean(raw); sdv <- sd(raw)
  cols <- paste0("cb_", v, "_", 1:4)
  coef <- colMeans(B[, cols]); vc <- cov(B[, cols])
  q <- quantile(raw, c(0.025, 0.1, 0.5, 0.9, 0.975))
  grid <- seq(q[1], q[5], length.out = 60)
  cp <- crosspred(CB[[v]], coef = coef, vcov = vc, model.link = "log",
                  at = (grid - mu) / sdv, cen = (q[3] - mu) / sdv)
  cum[[v]] <- data.frame(variable = v, value = grid, rr = cp$allRRfit, lo = cp$allRRlow, hi = cp$allRRhigh)
  cp2 <- crosspred(CB[[v]], coef = coef, vcov = vc, model.link = "log",
                   at = (q[c(2, 4)] - mu) / sdv, cen = (q[3] - mu) / sdv)
  for (k in 1:2) lagr[[length(lagr) + 1]] <- data.frame(
    variable = v, contrast = c("P10 vs median", "P90 vs median")[k], value = q[c(2, 4)][k], median = q[3],
    lag = 0:3, rr = cp2$matRRfit[k, ], lo = cp2$matRRlow[k, ], hi = cp2$matRRhigh[k, ],
    cum_rr = cp2$allRRfit[k], cum_lo = cp2$allRRlow[k], cum_hi = cp2$allRRhigh[k])
}
write.csv(bind_rows(cum), "out/exposure_response_cumulative.csv", row.names = FALSE)
L <- bind_rows(lagr)
write.csv(L, "out/exposure_response_lag.csv", row.names = FALSE)

env <- bind_rows(lapply(ENV, function(v) {
  b <- B[, paste0("env_", v)]; sdv <- sd(sp[[v]])
  data.frame(variable = v, sd = sdv, rr_per_sd = exp(mean(b)), lo = exp(quantile(b, 0.025)),
             hi = exp(quantile(b, 0.975)))
}))
write.csv(env, "out/exposure_response_env.csv", row.names = FALSE)

cat("\nCumulative rate ratio over lags 0-3, 10th and 90th percentile vs median (95% CrI):\n")
print(L |> distinct(variable, contrast, value, median, cum_rr, cum_lo, cum_hi) |>
        mutate(across(where(is.numeric), ~ round(.x, 3))) |> as.data.frame(), row.names = FALSE)
cat("\nLag-specific rate ratio, 90th percentile vs median:\n")
print(L |> filter(contrast == "P90 vs median") |> select(variable, lag, rr, lo, hi) |>
        mutate(across(where(is.numeric), ~ round(.x, 3))) |> as.data.frame(), row.names = FALSE)
cat("\nEnvironment terms, rate ratio per SD (previous-year shares; log night lights):\n")
print(env |> mutate(across(where(is.numeric), ~ signif(.x, 3))), row.names = FALSE)
