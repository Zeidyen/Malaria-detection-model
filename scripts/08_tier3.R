# Apply Tier 3 to every zone-adjusted flag from a model's predictions, 2018-2025.
# Usage: Rscript scripts/08_tier3.R [MODEL=arm]   (see scripts/lib_preds.R)
# Output: out/alerts_<MODEL>_2018_2025.csv (one row per flagged district-month), and a summary log.
suppressMessages(library(dplyr))
source("scripts/lib_tier3.R"); source("scripts/lib_preds.R")
MODEL <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "arm"
cases <- read.csv("data/derived/cases_district_month.csv")
ref <- tier3_reference(cases)
now <- cases |> transmute(unit, year, m, allout = allout_u5 + allout_5_14 + allout_ov15,
                          test = test_u5 + test_5_14 + test_ov15)
p <- load_preds(MODEL) |>
  left_join(now, by = c("unit", "year", "m")) |> left_join(ref, by = c("unit", "year", "m"))
t3 <- with(p, tier3_classify(conf_tot, allout, test, conf_ref, allout_ref, test_ref))
p <- bind_cols(p, t3)
al <- p |> filter(flag95_adj) |>
  select(unit, Region, District, zone, year, m, conf_tot, pred_med_adj, hi95_adj, R_zone,
         allout, test, pm_ratio, dtpr, tier3)
write.csv(al, sprintf("out/alerts_%s_2018_2025.csv", MODEL), row.names = FALSE)

cat("Model", MODEL, "| zone-adjusted flags, 2018-2025:", nrow(al), "of", nrow(p), "district-months\n\n")
cat("Tier 3 class by year:\n")
print(table(al$year, al$tier3))
cat("\nShare by class:\n"); print(round(prop.table(table(al$tier3)), 3))
cat("\nDistricts with most TRANSMISSION-class flags:\n")
print(al |> filter(tier3 == "transmission") |> count(Region, District, sort = TRUE) |> head(12) |>
        as.data.frame(), row.names = FALSE)
cat("\nCheck on 2021 (urban step changes; expected mostly reporting):\n")
print(al |> filter(year == 2021, District %in% c("Kumasi", "Ayawaso Central", "Sekondi-Takoradi",
        "Tema", "Krowor", "Achiase", "Birim South")) |> count(District, tier3) |> as.data.frame(), row.names = FALSE)
