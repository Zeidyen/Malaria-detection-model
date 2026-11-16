# Do the satellite layers help? (DESIGN.md s4 ablation, s9 item 12). Compares the main model
# (arm) with arm + satellite groups on the SAME real data and the SAME injected outbreaks.
# Usage: Rscript scripts/17_satellite_value.R arm sat-all sat-rain ...
# Needs, per model: monthly predictions (lib_preds.R), and out/cusum_<MODEL>.csv from 14_cusum.R
# (the "single" rows: one-month flag z > C for a grid of C).
# Accuracy (real data, 2018-25, zone-adjusted): CRPS, 95% coverage, share flagged.
# Detection AT A FIXED FALSE-ALERT RATE: sensitivity is interpolated (linear in the false-alert
# rate, across the C grid) to FA = 2%, so a model is not credited for simply alerting more.
# Output: out/satellite_value.csv, out/satellite_value_by_year.csv
suppressMessages(library(dplyr)); source("scripts/lib_preds.R")
MODELS <- commandArgs(TRUE); FA <- 0.02
acc <- bind_rows(lapply(MODELS, function(mo) load_preds(mo) |> mutate(model = mo)))
cov <- function(x) mean(x$conf_tot >= x$lo95_adj & x$conf_tot <= x$hi95_adj)
by_year <- acc |> group_by(model, year) |> group_modify(~ data.frame(crps = mean(.x$crps_adj), coverage = cov(.x),
                                                                      flagged = mean(.x$flag95_adj))) |> ungroup()
tot <- acc |> group_by(model) |> group_modify(~ data.frame(crps = mean(.x$crps_adj), coverage = cov(.x),
                                                            flagged = mean(.x$flag95_adj))) |> ungroup()
det <- bind_rows(lapply(MODELS, function(mo) {
  read.csv(sprintf("out/cusum_%s.csv", mo)) |> filter(rule == "single", type == "outbreak") |>
    group_by(k, L) |> arrange(false_alert_rate, .by_group = TRUE) |>
    summarise(sens = approx(false_alert_rate, sensitivity, xout = FA, ties = mean)$y, .groups = "drop") |>
    mutate(model = mo, cell = sprintf("+%d%%_%dmo", round((k - 1) * 100), L))
}))
tab <- det |> select(model, cell, sens) |> tidyr::pivot_wider(names_from = cell, values_from = sens) |>
  right_join(tot, by = "model")
write.csv(tab, "out/satellite_value.csv", row.names = FALSE)
write.csv(by_year, "out/satellite_value_by_year.csv", row.names = FALSE)
cat("Outbreak sensitivity at a fixed", FA * 100, "% false-alert rate, and accuracy, 2018-2025:\n")
print(tab |> mutate(across(where(is.numeric), ~ round(.x, 3))) |> as.data.frame(), row.names = FALSE)
cat("\nCRPS by year:\n")
print(by_year |> select(model, year, crps) |> mutate(crps = round(crps)) |>
        tidyr::pivot_wider(names_from = year, values_from = crps) |> as.data.frame(), row.names = FALSE)
