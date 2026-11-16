# Comparator 1: Farrington flexible (Noufaily et al. 2013), surveillance::farringtonFlexible,
# run separately on each district's monthly confirmed cases (DESIGN.md s6 item 3).
# Usage: Rscript scripts/11_farrington.R [MODEL=arm]
#
# Settings: b = 3 years back (b = 2 for 2018, the only year with < 3 full years of history),
# w = 1 month either side, Noufaily negative-binomial plug-in threshold ("nbPlugin"), trend kept only if significant, no population
# offset. alpha = one-sided level of the upper prediction limit; several values are run so the
# method can be compared with ours at a MATCHED false-alert rate, not only at its default (0.05).
#
# Synthetic events: the injected district-months saved by 09_synthetic.R (same events as our
# model). The upper limit for month t uses only months >= 11 months earlier (same calendar month
# +-1 in the previous b years), and each district has at most one event per year, so injections
# never enter a baseline: the limit is computed once on the real data and reused.
# Output: out/farrington_thresholds.csv, out/synthetic_farrington.csv (one row per type/k/L/alpha)
suppressMessages({library(dplyr); library(surveillance)})
MODEL <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "arm"
ALPHAS <- c(0.0001, 0.00025, 0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05)

cases <- read.csv("data/derived/cases_district_month.csv") |> arrange(unit, year, m)
units <- sort(unique(cases$unit))
Y <- matrix(cases$conf_tot, ncol = length(units))       # 132 months x 247 units (sorted by unit)
stopifnot(all(cases$unit[seq(1, nrow(cases), 132)] == units))
colnames(Y) <- units
s <- sts(observed = Y, start = c(2015, 1), frequency = 12)

run <- function(alpha, years, b) {
  idx <- which(rep(2015:2025, each = 12) %in% years)
  ctl <- list(range = idx, b = b, w = 1, alpha = alpha, thresholdMethod = "nbPlugin",
              reweight = TRUE, weightsThreshold = 2.58, trend = TRUE, pThresholdTrend = 0.05,
              populationOffset = FALSE, noPeriods = 1, pastWeeksNotIncluded = 1)
  r <- farringtonFlexible(s, control = ctl)
  data.frame(unit = rep(units, each = length(idx)),
             year = rep(2015:2025, each = 12)[idx], m = rep(1:12, 11)[idx],
             ub = as.vector(upperbound(r)), alpha = alpha)
}
th <- bind_rows(lapply(ALPHAS, function(a) bind_rows(run(a, 2018, 2), run(a, 2019:2025, 3))))
write.csv(th, "out/farrington_thresholds.csv", row.names = FALSE)

real <- th |> left_join(cases |> select(unit, year, m, conf_tot), by = c("unit", "year", "m")) |>
  mutate(flag = conf_tot > ub)
cat("Farrington on the real data, 2018-2025: share of district-months flagged\n")
print(real |> group_by(alpha) |> summarise(flagged = round(mean(flag, na.rm = TRUE), 4),
                                           na_ub = sum(is.na(ub))) |> as.data.frame(), row.names = FALSE)

inj <- read.csv(sprintf("out/synthetic_injections_%s.csv", MODEL))
out <- list()
for (a in ALPHAS) {
  ra <- real[real$alpha == a, ]
  e <- inj |> left_join(ra |> select(unit, year, m, ub, flag0 = flag), by = c("unit", "year", "m")) |>
    mutate(flag = conf > ub) |>
    group_by(type, k, L, year, rep, evid) |>
    summarise(detected = any(flag, na.rm = TRUE), detected0 = any(flag0, na.rm = TRUE),
              delay = if (any(flag, na.rm = TRUE)) which(flag)[1] - 1 else NA_real_, .groups = "drop")
  # false alerts: flag rate among the target year's district-months that carry no event
  fa <- inj |> distinct(type, k, L, year, rep, unit, m) |> mutate(inj = TRUE) |>
    group_by(type, k, L, year, rep) |> group_split() |>
    lapply(function(g) {
      x <- ra[ra$year == g$year[1], ] |> left_join(g |> select(unit, m, inj), by = c("unit", "m"))
      data.frame(type = g$type[1], k = g$k[1], L = g$L[1], false_rate = mean(x$flag[is.na(x$inj)], na.rm = TRUE))
    }) |> bind_rows()
  out[[length(out) + 1]] <- e |> group_by(type, k, L) |>
    summarise(events = n(), sensitivity = mean(detected), background = mean(detected0),
              median_delay = median(delay, na.rm = TRUE), .groups = "drop") |>
    left_join(fa |> group_by(type, k, L) |> summarise(false_alert_rate = mean(false_rate), .groups = "drop"),
              by = c("type", "k", "L")) |>
    mutate(method = "farrington", alpha = a)
}
S <- bind_rows(out)
write.csv(S, "out/synthetic_farrington.csv", row.names = FALSE)
cat("\nSynthetic events, Farrington (outbreaks):\n")
print(S |> filter(type == "outbreak") |> select(alpha, k, L, sensitivity, false_alert_rate) |>
        mutate(across(c(sensitivity, false_alert_rate), ~ round(.x, 3))) |> as.data.frame(), row.names = FALSE)
