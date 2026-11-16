# Multi-month accumulation rule (CUSUM) on top of the single-month alert (DESIGN.md s9 item 11).
# Usage: Rscript scripts/14_cusum.R [MODEL=arm]
#
# Standardised residual for each district-month, from the zone-adjusted predictive interval:
#   z = log(obs / med_adj) / s,  s = log(hi95 / med) / 1.96 if obs > med_adj, else log(med / lo95) / 1.96
# (scaling by R_loo cancels in the ratios, so z > 1.96 is exactly the existing single-month flag).
# Upper CUSUM per district, run continuously from Jan 2018:
#   C_t = max(0, C_{t-1} + z_t - K); alarm when C_t > H, then C resets to 0.
# Combined alert = single-month flag OR CUSUM alarm. The CUSUM is aimed at sustained rises that
# never cross the 95% limit in any single month (+25-50% for several months).
#
# Synthetic events: the injections saved by 09_synthetic.R, so results compare directly with 09,
# 11 and 12. An injection in year y changes z in year y only (R_loo recomputed for the zone-month,
# as in 09); the CUSUM runs over the real series from 2018 up to the end of y. As in 09, the model is
# not refitted after an injection, so later event months are somewhat optimistic.
# Fair test: the CUSUM is only worth adding if it beats simply LOWERING the single-month threshold
# (z > C, C < 1.96) at the same false-alert rate. Those rows have K = NA, H = NA and C set.
# Output: out/cusum_<MODEL>.csv (one row per K, H, type, k, L) and out/cusum_real_<MODEL>.csv
suppressMessages(library(dplyr)); source("scripts/lib_preds.R")
MODEL <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "arm"
GRID <- expand.grid(K = c(0.5, 1), H = c(2, 3, 4, 5, 6))
CS <- c(2.4, 2.25, 2.1, 1.96, 1.85, 1.75, 1.65, 1.55, 1.45)   # above 1.96 too, for matched-rate comparisons (17)

P <- load_preds(MODEL) |> arrange(year, m, unit) |>
  select(unit, zone, year, m, conf_tot, pred_med, lo95, hi95)
units <- sort(unique(P$unit)); nu <- length(units)
P$t <- (P$year - 2018) * 12 + P$m
stopifnot(all(P$unit == rep(units, 96)))            # 96 months x 247 units, unit fastest

zscore <- function(conf, x) {
  key <- paste(x$zone, x$year, x$m)
  to <- ave(conf, key, FUN = sum); tp <- ave(x$pred_med, key, FUN = sum)
  R <- (to - conf) / (tp - x$pred_med)
  med <- x$pred_med * R
  s <- ifelse(conf > med, log(x$hi95 / x$pred_med), log(x$pred_med / x$lo95)) / 1.96
  log(pmax(conf, 0.5) / med) / s
}
z0 <- zscore(P$conf_tot, P)
cat("Check: z > 1.96 share", round(mean(z0 > 1.96), 4), "(single-month flag rate of 09)\n")

# CUSUM over a 96 x 247 matrix of z (months x units); returns the alarm matrix
cusum <- function(Z, K, H) {
  A <- matrix(FALSE, nrow(Z), ncol(Z)); C <- rep(0, ncol(Z))
  for (i in seq_len(nrow(Z))) {
    C <- pmax(0, C + Z[i, ] - K)
    A[i, ] <- C > H; C[A[i, ]] <- 0
  }
  A
}
Z0 <- matrix(z0, nrow = 96, byrow = TRUE)
real <- bind_rows(lapply(seq_len(nrow(GRID)), function(g) {
  A <- cusum(Z0, GRID$K[g], GRID$H[g])
  data.frame(K = GRID$K[g], H = GRID$H[g], cusum_rate = mean(A), combined_rate = mean(A | Z0 > 1.96))
}))
cat("\nReal data, 2018-2025: share of district-months alerted\n")
print(real |> mutate(across(ends_with("rate"), ~ round(.x, 4))), row.names = FALSE)
write.csv(real, sprintf("out/cusum_real_%s.csv", MODEL), row.names = FALSE)

inj <- read.csv(sprintf("out/synthetic_injections_%s.csv", MODEL))
res <- list()
for (sp in split(inj, list(inj$type, inj$k, inj$L, inj$year, inj$rep), drop = TRUE)) {
  y <- sp$year[1]
  rows <- which(P$year == y)
  conf <- P$conf_tot
  hit <- match(paste(sp$unit, sp$m), paste(P$unit[rows], P$m[rows]))
  conf[rows[hit]] <- sp$conf
  Z <- Z0
  Z[(y - 2018) * 12 + 1:12, ] <- matrix(zscore(conf[rows], P[rows, ]), nrow = 12, byrow = TRUE)
  Z <- Z[seq_len((y - 2018) * 12 + 12), , drop = FALSE]
  ev <- matrix(NA_integer_, 12, nu); ev[cbind(sp$m, match(sp$unit, units))] <- sp$evid
  yr <- (y - 2018) * 12 + 1:12
  for (g in seq_len(nrow(GRID))) {
    A <- cusum(Z, GRID$K[g], GRID$H[g])[yr, ]
    A0 <- cusum(Z0[seq_len(max(yr)), ], GRID$K[g], GRID$H[g])[yr, ]
    single <- Z[yr, ] > 1.96; single0 <- Z0[yr, ] > 1.96
    onev <- !is.na(ev)
    d <- data.frame(evid = ev[onev], mo = row(ev)[onev], cus = A[onev], comb = (A | single)[onev],
                    comb0 = (A0 | single0)[onev])
    e <- d |> arrange(evid, mo) |> group_by(evid) |>
      summarise(det_cusum = any(cus), det_comb = any(comb), det_comb0 = any(comb0),
                delay = if (any(comb)) which(comb)[1] - 1 else NA_real_, .groups = "drop")
    res[[length(res) + 1]] <- data.frame(type = sp$type[1], k = sp$k[1], L = sp$L[1], year = y,
      K = GRID$K[g], H = GRID$H[g], C = 1.96, n = nrow(e), det_cusum = sum(e$det_cusum),
      det_comb = sum(e$det_comb), det_comb0 = sum(e$det_comb0),
      delay_sum = sum(e$delay, na.rm = TRUE), false_rate = mean((A | single)[!onev]))
  }
  for (C in CS) {
    single <- Z[yr, ] > C; single0 <- Z0[yr, ] > C; onev <- !is.na(ev)
    e <- data.frame(evid = ev[onev], mo = row(ev)[onev], f = single[onev], f0 = single0[onev]) |>
      arrange(evid, mo) |> group_by(evid) |>
      summarise(det = any(f), det0 = any(f0), delay = if (any(f)) which(f)[1] - 1 else NA_real_, .groups = "drop")
    res[[length(res) + 1]] <- data.frame(type = sp$type[1], k = sp$k[1], L = sp$L[1], year = y,
      K = NA, H = NA, C = C, n = nrow(e), det_cusum = NA, det_comb = sum(e$det), det_comb0 = sum(e$det0),
      delay_sum = sum(e$delay, na.rm = TRUE), false_rate = mean(single[!onev]))
  }
}
res <- bind_rows(res)
S <- res |> mutate(rule = ifelse(is.na(K), "single", "single+cusum")) |> group_by(rule, type, k, L, K, H, C) |>
  summarise(events = sum(n), sens_cusum_only = sum(det_cusum) / sum(n),
            sensitivity = sum(det_comb) / sum(n), background = sum(det_comb0) / sum(n),
            mean_delay = sum(delay_sum) / sum(det_comb), false_alert_rate = mean(false_rate), .groups = "drop")
write.csv(S, sprintf("out/cusum_%s.csv", MODEL), row.names = FALSE)
cat("\nSynthetic OUTBREAKS: single-month flag OR CUSUM (rule single+cusum), vs single flag at lower thresholds C:\n")
print(S |> filter(type == "outbreak") |> select(rule, K, H, C, k, L, sensitivity, false_alert_rate) |>
        mutate(across(c(sensitivity, false_alert_rate), ~ round(.x, 3))) |> as.data.frame(), row.names = FALSE)
