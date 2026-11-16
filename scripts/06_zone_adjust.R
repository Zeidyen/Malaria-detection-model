# Two-tier alerts (proposed fix for system-wide shifts seen in the 2018-25 baseline runs).
# Tier 1 (zone shift): observed / predicted for the zone-month, all districts together.
# Tier 2 (district anomaly): each district's prediction is rescaled by the zone-month ratio
#   computed from the OTHER districts in its zone (leave-one-district-out), so a shift that hits
#   the whole zone is not counted as a local anomaly. All districts report the same month, so
#   this uses only information available in real time.
# Approximation: quantiles are rescaled by the ratio; the ratio's own uncertainty is ignored
# (each zone has 55-108 districts, so it is precise). A proper version puts a zone x month
# effect inside the model.
suppressMessages(library(dplyr))
o <- read.csv("out/baseline_all_years_pred.csv")
o <- o |> group_by(zone, year, m) |>
  mutate(R_loo = (sum(conf_tot) - conf_tot) / (sum(pred_med) - pred_med),
         R_zone = sum(conf_tot) / sum(pred_med)) |> ungroup() |>
  mutate(hi95_adj = hi95 * R_loo, lo95_adj = lo95 * R_loo, flag95_adj = conf_tot > hi95_adj)
zm <- o |> distinct(zone, year, m, R_zone)
cat("Zone-months with a system-wide shift (|obs/pred - 1| > 20%):",
    sum(abs(zm$R_zone - 1) > 0.2), "of", nrow(zm), "\n")
print(zm |> filter(abs(R_zone - 1) > 0.2) |> count(year, zone) |> as.data.frame(), row.names = FALSE)
cat("\nDistrict flags before vs after zone adjustment:\n")
print(o |> group_by(year) |> summarise(flag_before = round(mean(flag95), 3), flag_after = round(mean(flag95_adj), 3),
  cover_after = round(mean(conf_tot >= lo95_adj & conf_tot <= hi95_adj), 3),
  dist_3plus_after = round(mean(tapply(flag95_adj, unit, sum) >= 3), 3)) |> as.data.frame(), row.names = FALSE)
write.csv(o, "out/baseline_all_years_zoneadj.csv", row.names = FALSE)
