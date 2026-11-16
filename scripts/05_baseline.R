# Calendar baseline: the model every climate / satellite model must beat (DESIGN.md s4-5).
# No climate, satellite or intervention terms. One rolling-origin step: fit on years before
# TARGET, predict every district-month of TARGET, then flag months above the upper prediction
# limit. This is the end-to-end check of the pipeline; the full rolling loop comes later.
#
# Model (negative binomial, R-INLA):
#   conf_tot ~ offset(log pop_tot) + month (cyclic RW2, one curve per ecological zone)
#              + BYM2 district effect + IID year effect
#              + district-specific linear trend (TREND=1, default; TREND=0 drops it)
#   Without the trend, districts whose level shifted over the decade (urban Accra, North-East
#   Gonja) are flagged in nearly every month of the target year: a level shift, not an outbreak.
# Prediction intervals come from posterior samples of the linear predictor plus
# negative-binomial observation noise; the year effect for TARGET is drawn from its prior,
# because a future year is unknown at the time of prediction.
#
# Usage: Rscript scripts/05_baseline.R [TARGET=2023] [TREND=1]
# Output: out/baseline_<TARGET>[_notrend]_pred.csv
suppressMessages({library(dplyr); library(sf); library(INLA)}); sf_use_s2(FALSE)
args <- commandArgs(TRUE)
TARGET <- if (length(args)) as.integer(args[1]) else 2023L
TREND <- if (length(args) > 1) as.integer(args[2]) else 1L
TAG <- if (TREND == 1) "" else "_notrend"
NSAMP <- 500
set.seed(20261027)

# Ghana's three broad ecological belts (Guinea savannah north, forest and transition middle
# belt, coastal savannah south), assigned by region. Rainfall is unimodal in the north and
# bimodal further south, hence one seasonal curve per zone.
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
  filter(year <= TARGET) |>
  mutate(zone = ZONE[Region], z = as.integer(factor(zone, levels = c("North", "Forest", "Coast"))),
         sid = match(unit, u$unit), yid = year - min(year) + 1,
         y = ifelse(year == TARGET, NA, conf_tot),
         sid2 = sid, tc = (year - TARGET) / 5)   # trend, centred on the target year
stopifnot(!anyNA(d$zone), !anyNA(d$sid))

pc_prec <- list(prec = list(prior = "pc.prec", param = c(1, 0.01)))
f <- y ~ 1 + offset(log(pop_tot)) +
  f(m, model = "rw2", cyclic = TRUE, group = z, control.group = list(model = "iid"),
    hyper = pc_prec, scale.model = TRUE) +
  f(sid, model = "bym2", graph = G, scale.model = TRUE,
    hyper = list(prec = list(prior = "pc.prec", param = c(1, 0.01)),
                 phi = list(prior = "pc", param = c(0.5, 0.5)))) +
  f(yid, model = "iid", hyper = pc_prec)
if (TREND == 1) f <- update(f, . ~ . + f(sid2, tc, model = "iid", hyper = pc_prec))

t0 <- Sys.time()
fit <- inla(f, family = "nbinomial", data = d,
            control.predictor = list(compute = TRUE, link = 1),
            control.compute = list(config = TRUE, dic = FALSE, waic = FALSE),
            num.threads = "4:1", verbose = FALSE)
cat("fit", TARGET, "trend", TREND, "in", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")
print(fit$summary.hyperpar[, c("mean", "0.025quant", "0.975quant")])

# ---- predictive distribution for the target year ---------------------------------------
idx <- which(d$year == TARGET)
s <- inla.posterior.sample(NSAMP, fit, num.threads = "4:1")
eta_rows <- grep("^Predictor:", rownames(s[[1]]$latent))[idx]
yid_rows <- grep("^yid:", rownames(s[[1]]$latent))
tyid <- unique(d$yid[idx])
draw <- sapply(s, function(x) {
  h <- x$hyperpar
  size <- h[grep("size", names(h))]
  # replace the (unidentified) target-year effect with a draw from its fitted prior
  yr_prec <- h[grep("yid", names(h))]
  eta <- x$latent[eta_rows] - x$latent[yid_rows[tyid]] + rnorm(1, 0, 1 / sqrt(yr_prec))
  rnbinom(length(eta), size = size, mu = exp(eta))
})

obs <- d$conf_tot[idx]
q <- t(apply(draw, 1, quantile, c(0.025, 0.5, 0.95, 0.975, 0.995)))
# sample-based CRPS: E|X - y| - 0.5 E|X - X'|
crps <- sapply(seq_along(obs), function(i) {
  x <- draw[i, ]; mean(abs(x - obs[i])) - 0.5 * mean(abs(x - sample(x)))
})
pit <- rowMeans(draw < obs) + 0.5 * rowMeans(draw == obs)
out <- d[idx, c("unit", "Region", "District", "zone", "year", "m", "pop_tot", "conf_tot")] |>
  mutate(pred_med = q[, 2], lo95 = q[, 1], hi95 = q[, 4], hi90 = q[, 3], hi99 = q[, 5],
         crps = crps, pit = pit, flag95 = conf_tot > hi95, flag99 = conf_tot > hi99)
write.csv(out, sprintf("out/baseline_%d%s_pred.csv", TARGET, TAG), row.names = FALSE)

cat(sprintf("\nTarget %d: %d district-months\n", TARGET, nrow(out)))
cat(sprintf("95%% interval coverage: %.3f (nominal 0.95)\n", mean(obs >= q[, 1] & obs <= q[, 4])))
cat(sprintf("Flagged above upper 95%%: %.3f | above upper 99.5%%: %.3f\n", mean(out$flag95), mean(out$flag99)))
cat(sprintf("Mean CRPS: %.1f cases | median abs error of median: %.1f\n", mean(crps), median(abs(obs - q[, 2]))))
cat("PIT deciles (flat = calibrated):", round(as.numeric(table(cut(pit, seq(0, 1, 0.1), include.lowest = TRUE))) / length(pit), 3), "\n")
cat("\nBy zone:\n")
print(out |> group_by(zone) |> summarise(coverage95 = mean(conf_tot >= lo95 & conf_tot <= hi95),
  flagged95 = mean(flag95), crps = mean(crps), obs = sum(conf_tot), pred = sum(pred_med)) |> as.data.frame())
cat("\nMost-flagged districts (months above upper 95%):\n")
print(out |> group_by(Region, District) |> summarise(n_flag = sum(flag95), .groups = "drop") |>
        arrange(desc(n_flag)) |> head(10) |> as.data.frame(), row.names = FALSE)
