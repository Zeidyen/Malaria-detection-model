# Uncertainty of the satellite gain (DESIGN.md s9 item 12): paired district bootstrap.
# Usage: Rscript scripts/20_bootstrap.R [BASE=arm] [NEW=sat-all] [B=2000]
#
# For each model, the standardised residual z of every district-month in every injected set
# (same injections as 09, 11-14; zone-month leave-one-out ratio recomputed as in 14_cusum.R) gives,
# for each threshold C in a grid:
#   per district: outbreaks detected (any month of the event with z > C), outbreaks injected,
#                 non-event months with z > C, non-event months.
# One bootstrap replicate draws the 247 districts with replacement (the same draw for both models,
# so the comparison is paired) and recomputes, per outbreak size x duration cell, sensitivity and
# false-alert rate at every C, then sensitivity at a FIXED 2% false-alert rate (linear interpolation
# over C, as in 17_satellite_value.R). Resampling whole districts keeps each district's events,
# false alerts and their correlation together.
# Output: out/bootstrap_<BASE>_vs_<NEW>.csv (point estimates and 95% percentile intervals)
suppressMessages(library(dplyr)); source("scripts/lib_preds.R")
a <- commandArgs(TRUE)
BASE <- if (length(a) > 0) a[1] else "arm"
NEW <- if (length(a) > 1) a[2] else "sat-all"
B <- if (length(a) > 2) as.integer(a[3]) else 2000
FA <- 0.02
CS <- seq(1.3, 2.8, by = 0.05)
set.seed(20261030)

zscore <- function(conf, x) {
  key <- paste(x$zone, x$year, x$m)
  to <- ave(conf, key, FUN = sum); tp <- ave(x$pred_med, key, FUN = sum)
  R <- (to - conf) / (tp - x$pred_med)
  med <- x$pred_med * R
  s <- ifelse(conf > med, log(x$hi95 / x$pred_med), log(x$pred_med / x$lo95)) / 1.96
  log(pmax(conf, 0.5) / med) / s
}

inj <- read.csv(sprintf("out/synthetic_injections_%s.csv", NEW)) |> filter(type == "outbreak")
stopifnot(identical(inj, read.csv(sprintf("out/synthetic_injections_%s.csv", BASE)) |> filter(type == "outbreak")))
units <- NULL

# per model: list over cells of arrays [unit, C] for det, nev, fl, nm
tally <- function(model) {
  P <- load_preds(model) |> arrange(year, m, unit) |> select(unit, zone, year, m, conf_tot, pred_med, lo95, hi95)
  units <<- sort(unique(P$unit)); nu <- length(units)
  out <- list()
  for (sp in split(inj, list(inj$k, inj$L, inj$year, inj$rep), drop = TRUE)) {
    cell <- sprintf("+%d%%_%dmo", round((sp$k[1] - 1) * 100), sp$L[1])
    rows <- which(P$year == sp$year[1]); x <- P[rows, ]
    conf <- x$conf_tot
    hit <- match(paste(sp$unit, sp$m), paste(x$unit, x$m))
    conf[hit] <- sp$conf
    z <- zscore(conf, x)
    ui <- match(x$unit, units)
    ev <- rep(NA_integer_, nrow(x)); ev[hit] <- sp$evid
    if (is.null(out[[cell]])) out[[cell]] <- list(det = matrix(0, nu, length(CS)), nev = numeric(nu),
                                                  fl = matrix(0, nu, length(CS)), nm = numeric(nu))
    o <- out[[cell]]
    non <- is.na(ev)
    o$nm <- o$nm + tabulate(ui[non], nu)
    for (j in seq_along(CS)) {
      o$fl[, j] <- o$fl[, j] + tabulate(ui[non & z > CS[j]], nu)
      d <- tapply(z[!non] > CS[j], ev[!non], any)                  # detected per event
      eu <- ui[!non][match(names(d), ev[!non])]                      # event's district
      o$det[, j] <- o$det[, j] + tabulate(eu[d], nu)
    }
    eu_all <- ui[!non][!duplicated(ev[!non])]
    o$nev <- o$nev + tabulate(eu_all, nu)
    out[[cell]] <- o
  }
  out
}
tb <- tally(BASE); tn <- tally(NEW)
nu <- length(units)

at_fa <- function(o, w) {
  sens <- colSums(o$det * w) / sum(o$nev * w)
  far <- colSums(o$fl * w) / sum(o$nm * w)
  approx(far, sens, xout = FA, ties = mean, rule = 2)$y
}
W <- rmultinom(B, nu, rep(1, nu))                                    # nu x B district counts
res <- bind_rows(lapply(names(tb), function(cell) {
  p0 <- at_fa(tb[[cell]], rep(1, nu)); p1 <- at_fa(tn[[cell]], rep(1, nu))
  bs0 <- apply(W, 2, function(w) at_fa(tb[[cell]], w))
  bs1 <- apply(W, 2, function(w) at_fa(tn[[cell]], w))
  q <- function(v) quantile(v, c(0.025, 0.975), na.rm = TRUE)
  data.frame(cell = cell, base = p0, base_lo = q(bs0)[1], base_hi = q(bs0)[2],
             new = p1, new_lo = q(bs1)[1], new_hi = q(bs1)[2],
             gain = p1 - p0, gain_lo = q(bs1 - bs0)[1], gain_hi = q(bs1 - bs0)[2],
             p_gain_le_0 = mean(bs1 - bs0 <= 0))
}))
rownames(res) <- NULL
res <- res[order(match(res$cell, c("+25%_1mo", "+25%_3mo", "+50%_1mo", "+50%_3mo", "+100%_1mo", "+100%_3mo"))), ]
write.csv(res, sprintf("out/bootstrap_%s_vs_%s.csv", BASE, NEW), row.names = FALSE)
cat(sprintf("Outbreak sensitivity at a fixed %.0f%% false-alert rate, %s vs %s, %d district bootstrap replicates:\n",
            FA * 100, BASE, NEW, B))
print(res |> mutate(across(where(is.numeric), ~ round(.x, 3))), row.names = FALSE)
