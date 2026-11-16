# National DHIMS2 district-month malaria cases, 2015-2025: quality check and boundary match.
# Input : data/raw/dhims_national_2015_2025.csv (see data/raw/README.md)
#         (Zeid's DHIMS2 extract of 9 Oct 2026, prepared by that project's 00_dhims_prepare.R)
#         data/raw/gha_ADM2.geojson (geoBoundaries, 260)
# Output: data/derived/cases_district_month.csv, out/logs/01_cases_qa.log
suppressMessages({library(dplyr); library(sf)})
SRC <- "data/raw"
d <- read.csv(file.path(SRC, "dhims_national_2015_2025.csv"), check.names = FALSE)
cat("rows", nrow(d), "| districts", n_distinct(d$District), "| regions", n_distinct(d$Region),
    "| months", n_distinct(paste(d$year, d$m)), "\n")

ages <- c("u5", "5_14", "ov15")
cols <- c(paste0("susp_", ages), paste0("test_", ages), paste0("conf_", ages), paste0("allout_", ages))
cat("\nNA cells:", sum(is.na(d[, cols])), "\n")
cat("\nNegative / zero values per column:\n")
print(data.frame(col = cols, neg = sapply(cols, \(c) sum(d[[c]] < 0)), zero = sapply(cols, \(c) sum(d[[c]] == 0))), row.names = FALSE)
cat("\nLogical violations (count of district-months):\n")
for (a in ages) cat(sprintf("  %-5s conf > test %4d | test > susp %4d | susp > allout %4d\n", a,
  sum(d[[paste0("conf_", a)]] > d[[paste0("test_", a)]]),
  sum(d[[paste0("test_", a)]] > d[[paste0("susp_", a)]]),
  sum(d[[paste0("susp_", a)]] > d[[paste0("allout_", a)]])))

# Extreme jumps: month value > 5x the district median for that series
d <- d |> group_by(District) |> mutate(across(all_of(paste0("conf_", ages)), ~ .x / median(.x), .names = "r_{.col}")) |> ungroup()
cat("\nDistrict-months with confirmed > 5x the district median:\n")
for (a in ages) cat(sprintf("  %-5s %d\n", a, sum(d[[paste0("r_conf_", a)]] > 5)))
top <- d |> mutate(r = pmax(r_conf_u5, r_conf_5_14, r_conf_ov15)) |> arrange(desc(r)) |>
  select(Region, District, year, m, conf_u5, conf_5_14, conf_ov15, r) |> head(15)
print(as.data.frame(top), row.names = FALSE)

# Repeated identical values across consecutive months (a sign of carried-forward imputation)
rep_run <- d |> arrange(District, year, m) |> group_by(District) |>
  summarise(same_as_prev = sum(conf_tot == lag(conf_tot), na.rm = TRUE), .groups = "drop")
cat("\nConsecutive identical conf_tot months: total", sum(rep_run$same_as_prev),
    "| districts with any", sum(rep_run$same_as_prev > 0), "\n")

# ---- match all 248 districts to geoBoundaries ADM2 ----------------------------------
sf_use_s2(FALSE)
adm2 <- st_read(file.path(SRC, "gha_ADM2.geojson"), quiet = TRUE)
norm <- function(v) gsub("[^a-z]", "", tolower(v))
adm2$key <- norm(adm2$shapeName)
dk <- unique(d$adm2_key)
cat("\nDHIMS districts", length(dk), "| ADM2 polygons", nrow(adm2),
    "| matched", sum(dk %in% adm2$key), "\n")
cat("Unmatched DHIMS keys:\n"); print(sort(setdiff(dk, adm2$key)))
cat("ADM2 polygons with no DHIMS district:\n"); print(sort(setdiff(adm2$key, dk)))
