# Spatially clustered upsurges (DESIGN.md s9 item 16). The main validation (09) injects each upsurge
# into ONE district. Real upsurges cluster (a flood hits a valley), and the zone adjustment divides
# by the leave-one-out zone-month ratio, so a rise shared by neighbours can partly cancel itself.
# Usage: Rscript scripts/23_clustered.R [MODEL=sat-all]
#
# Clusters: a random seed district plus (size - 1) of its neighbours (first-order, then second-order if
# too few), all with the same start month, size multiplier k and duration L. Sizes 1 (isolated,
# reference), 3, 5, 10 and 20. Per injected set: 4 non-overlapping clusters. Injection as in 09 (type
# "outbreak": extra cases ~ Poisson((k - 1) * observed)). k in {1.5, 2}, L in {1, 3}, 2018-2025, 5 sets
# per year.
# Scored three ways: zone-ADJUSTED z (the system), RAW z (no zone adjustment), and EITHER (flag when
# max(adjusted, raw) is high: local OR widespread rises), each at a FIXED 2%
# false-alert rate (threshold grid on the standardised residual, as in 14/17/20), because the raw
# rule flags more months overall.
# Sensitivity is per district (each district of a cluster counts as one event; detected if flagged in
# any of its event months), and per cluster (at least one of its districts flagged).
# Output: out/clustered_<MODEL>.csv
suppressMessages({library(dplyr); library(sf)}); sf_use_s2(FALSE)
source("scripts/lib_preds.R")
MODEL <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "sat-all"
set.seed(20261031)
NREP <- 5; NCL <- 4; FA <- 0.02   # 4 clusters per set so that 4 x 20 districts fit without overlap
CS <- seq(1.2, 3.0, by = 0.05)
GRID <- expand.grid(size = c(1, 3, 5, 10, 20), k = c(1.5, 2), L = c(1, 3))

u <- st_read("data/derived/units.gpkg", quiet = TRUE)
nb <- st_relate(u, u, pattern = "F***1****")
names(nb) <- u$unit
P <- load_preds(MODEL) |> arrange(year, m, unit) |> select(unit, zone, year, m, conf_tot, pred_med, lo95, hi95)

zs <- function(conf, x, adjust) {
  if (adjust) {
    key <- paste(x$zone, x$m)
    to <- ave(conf, key, FUN = sum); tp <- ave(x$pred_med, key, FUN = sum)
    R <- (to - conf) / (tp - x$pred_med)
  } else R <- 1
  med <- x$pred_med * R
  s <- ifelse(conf > med, log(x$hi95 / x$pred_med), log(x$pred_med / x$lo95)) / 1.96
  log(pmax(conf, 0.5) / med) / s
}

make_cluster <- function(size, taken) {
  for (try in 1:200) {
    seed <- sample(setdiff(u$unit, taken), 1)
    if (size == 1) return(seed)
    cl <- seed                                  # grow by rings of neighbours until big enough
    while (length(cl) < size) {
      ring <- setdiff(u$unit[unique(unlist(nb[cl]))], c(cl, taken))
      if (!length(ring)) break
      need <- size - length(cl)
      cl <- c(cl, if (length(ring) <= need) ring else sample(ring, need))
    }
    if (length(cl) == size) return(cl)
  }
  stop("no cluster found")
}

rows_out <- list()
for (g in seq_len(nrow(GRID))) {
  size <- GRID$size[g]; k <- GRID$k[g]; L <- GRID$L[g]
  acc <- list(adj = list(det = 0, n = 0, cdet = 0, cn = 0, fl = 0, nm = 0), raw = NULL)
  tot <- list()
  for (y in 2018:2025) {
    x <- P[P$year == y, ]
    for (r in seq_len(NREP)) {
      conf <- x$conf_tot; evid <- rep(NA_integer_, nrow(x)); clid <- rep(NA_integer_, nrow(x))
      taken <- character(0); id <- 0
      for (cl in seq_len(NCL)) {
        cu <- make_cluster(size, taken); taken <- c(taken, cu)
        st <- sample(1:(13 - L), 1)
        for (un in cu) {
          rr <- which(x$unit == un & x$m >= st & x$m < st + L)
          id <- id + 1; evid[rr] <- id; clid[rr] <- cl
          conf[rr] <- conf[rr] + rpois(length(rr), (k - 1) * conf[rr])
        }
      }
      inj <- !is.na(evid)
      za <- zs(conf, x, TRUE); zr <- zs(conf, x, FALSE)
      for (rl in c("zone-adjusted", "raw", "either")) {
        z <- switch(rl, "zone-adjusted" = za, raw = zr, either = pmax(za, zr))
        for (j in seq_along(CS)) {
          f <- z > CS[j]
          d_ev <- tapply(f[inj], evid[inj], any)
          d_cl <- tapply(f[inj], clid[inj], any)
          tot[[length(tot) + 1]] <- data.frame(rule = rl, C = CS[j], det = sum(d_ev), n = length(d_ev),
                                               cdet = sum(d_cl), cn = length(d_cl), fl = sum(f[!inj]), nm = sum(!inj))
        }
      }
    }
  }
  s <- bind_rows(tot) |> group_by(rule, C) |>
    summarise(sens = sum(det) / sum(n), csens = sum(cdet) / sum(cn), far = sum(fl) / sum(nm), .groups = "drop")
  for (rl in c("zone-adjusted", "raw", "either")) {
    v <- s[s$rule == rl, ] |> arrange(far)
    at196 <- s[s$rule == rl & abs(s$C - 1.95) < 1e-9, ]   # nearest grid point to the 95% limit
    rows_out[[length(rows_out) + 1]] <- data.frame(size = size, k = k, L = L, rule = rl,
      sens_district_at2 = approx(v$far, v$sens, xout = FA, ties = mean, rule = 2)$y,
      sens_cluster_at2 = approx(v$far, v$csens, xout = FA, ties = mean, rule = 2)$y,
      sens_district_95 = at196$sens, far_95 = at196$far)
  }
  cat("done size", size, "k", k, "L", L, "\n")
}
R <- bind_rows(rows_out)
write.csv(R, sprintf("out/clustered_%s.csv", MODEL), row.names = FALSE)
cat("\nUpsurge sensitivity by cluster size; fixed 2% false-alert rate (and at the 95% limit):\n")
print(R |> mutate(across(c(sens_district_at2, sens_cluster_at2, sens_district_95, far_95), ~ round(.x, 3))) |>
        arrange(k, L, rule, size) |> as.data.frame(), row.names = FALSE)
