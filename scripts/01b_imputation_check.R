# Look for signatures of upstream imputation in the national DHIMS2 extract (Zeid confirmed
# 2026-10-27 that it was cleaned/imputed before it reached him; method unknown).
# Uses the raw per-district file (before the Guan+Hohoe merge).
suppressMessages(library(dplyr))
d <- read.csv("data/raw/dhims_national_2015_2025.csv",
              check.names = FALSE) |> arrange(District, year, m)
vars <- c("conf_u5", "conf_5_14", "conf_ov15", "test_u5", "susp_u5")
n <- nrow(d)
cat("district-months:", n, "\n\n")
res <- lapply(vars, function(v) {
  x <- d |> group_by(District) |> mutate(
    prev = lag(.data[[v]]), nxt = lead(.data[[v]]), val = .data[[v]],
    int = !is.na(prev) & !is.na(nxt) & abs(val - (prev + nxt) / 2) <= 0.5 & prev != nxt,
    carry = !is.na(prev) & val == prev,
    dmean = abs(val - round(mean(val))) <= 0.5,
    dmed = val == median(val),
    nonint = val != round(val)) |>
    group_by(District, m) |> mutate(cmean = abs(val - round(mean(val))) <= 0.5) |> ungroup()
  data.frame(var = v, interp_midpoint = sum(x$int), carry_forward = sum(x$carry),
             eq_district_mean = sum(x$dmean), eq_district_median = sum(x$dmed),
             eq_calendar_month_mean = sum(x$cmean), non_integer = sum(x$nonint))
})
print(do.call(rbind, res), row.names = FALSE)

# Expected by chance: for counts in the hundreds-thousands, an exact midpoint or exact mean
# should occur in well under 1% of months. Districts with clusters are listed.
x <- d |> group_by(District) |> mutate(int = abs(conf_u5 - (lag(conf_u5) + lead(conf_u5)) / 2) <= 0.5 &
                                          lag(conf_u5) != lead(conf_u5)) |>
  summarise(n_int = sum(int, na.rm = TRUE), .groups = "drop") |> arrange(desc(n_int))
cat("\nDistricts with most exact-midpoint conf_u5 months:\n"); print(head(as.data.frame(x), 10), row.names = FALSE)

# Fixed age split: identical u5 share of confirmed in consecutive months
s <- d |> group_by(District) |> mutate(sh = round(conf_u5 / conf_tot, 4), same = sh == lag(sh)) |> ungroup()
cat("\nConsecutive months with identical u5 share (4 dp):", sum(s$same, na.rm = TRUE), "\n")

# Presumed cases and the 'adj1_conf' column: is adj1_conf = conf + pres * TPR?
chk <- with(d, adj1_conf - (conf_tot + pres_tot * conf_tot / pmax(test_tot, 1)))
cat("\nadj1_conf vs conf + presumed x TPR: median abs diff", round(median(abs(chk)), 1),
    "| share within 5:", round(mean(abs(chk) <= 5), 3), "\n")
cat("adj1_conf / conf_tot: median", round(median(d$adj1_conf / pmax(d$conf_tot, 1)), 3), "\n")

# ---- chance baseline: exact match vs near misses ---------------------------------------
# Imputation leaves a SPIKE at offset 0 (exact midpoint / exact repeat). Chance gives a
# flat profile across small offsets. Ratio = count at 0 / mean count at offsets +-1..3.
cat("\nSpike test (count at offset 0 vs mean of offsets +-1..3; ratio ~1 = chance):\n")
for (v in vars) {
  x <- d |> group_by(District) |> mutate(val = .data[[v]], p = lag(val), q = lead(val)) |> ungroup() |>
    filter(!is.na(p), !is.na(q))
  dm <- 2 * x$val - (x$p + x$q)   # twice the gap to the midpoint (integer)
  dc <- x$val - x$p               # gap to previous month
  mid0 <- sum(dm == 0 & x$p != x$q); midn <- mean(sapply(c(-6, -4, -2, 2, 4, 6), \(k) sum(dm == k)))
  car0 <- sum(dc == 0); carn <- mean(sapply(c(-3:-1, 1:3), \(k) sum(dc == k)))
  cat(sprintf("  %-10s midpoint %4d vs %6.1f (ratio %.2f) | repeat %4d vs %6.1f (ratio %.2f)\n",
              v, mid0, midn, mid0 / midn, car0, carn, car0 / carn))
}
