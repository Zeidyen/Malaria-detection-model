# Real-event check (DESIGN.md s9 item 14): did the system flag districts during documented floods
# and reported malaria upsurges, 2018-2025? Events: data/derived/real_events.csv, compiled from
# docs/real_events_sources.md (IFRC, NADMO via news, GHS statements; every event sourced).
# Usage: Rscript scripts/21_real_events.R [MODELS = sat-all arm]
#
# Window: the event's start month and the 2 months after (malaria follows flooding with a lag of
# about one month). For each event-district: any zone-adjusted flag in the window, the Tier 3 class
# of those flags, and observed / expected (zone-adjusted median) over the window.
# Reference: the SAME district and SAME calendar months in the other years 2018-2025, so a district
# that is flagged often anyway does not count as a hit.
# This is a plausibility check, not a validation: a flood need not raise malaria (people move, nets
# are distributed, facilities close and reporting drops), and documented events are few.
# Output: out/real_events_<MODEL>.csv
suppressMessages(library(dplyr)); source("scripts/lib_preds.R"); source("scripts/lib_tier3.R")
MODELS <- if (length(commandArgs(TRUE))) commandArgs(TRUE) else c("sat-all", "arm")
ev <- read.csv("data/derived/real_events.csv")
win <- bind_rows(lapply(seq_len(nrow(ev)), function(i) {
  e <- ev[i, ]
  expand.grid(unit = strsplit(e$units, ";")[[1]], m = e$m_start:e$m_end, stringsAsFactors = FALSE) |>
    mutate(event = e$event, type = e$type, year = e$year)
}))
cases <- read.csv("data/derived/cases_district_month.csv")
stopifnot(all(win$unit %in% cases$unit))
for (mo in MODELS) {
  p <- load_preds(mo)
  al <- read.csv(sprintf("out/alerts_%s_2018_2025.csv", mo))
  p <- p |> left_join(al |> select(unit, year, m, tier3), by = c("unit", "year", "m"))
  inwin <- win |> left_join(p, by = c("unit", "year", "m"))
  ref <- win |> distinct(event, unit, m, year) |> rename(ev_year = year) |>
    inner_join(p, by = c("unit", "m"), relationship = "many-to-many") |> filter(year != ev_year) |>
    group_by(event, unit, year) |> summarise(flag = any(flag95_adj), .groups = "drop") |>
    group_by(event, unit) |> summarise(ref_flag_share = mean(flag), .groups = "drop")
  r <- inwin |> group_by(event, type, year, unit) |>
    summarise(flagged = any(flag95_adj), months_flagged = sum(flag95_adj),
              classes = paste(na.omit(tier3), collapse = ","),
              obs_exp = sum(conf_tot) / sum(pred_med_adj), .groups = "drop") |>
    left_join(ref, by = c("event", "unit"))
  write.csv(r, sprintf("out/real_events_%s.csv", mo), row.names = FALSE)
  cat("\n=====", mo, "=====\n")
  print(r |> group_by(event, type, year) |>
          summarise(districts = n(), flagged = sum(flagged), expected_by_chance = round(sum(ref_flag_share), 1),
                    obs_exp_median = round(median(obs_exp), 2),
                    classes = paste(unique(unlist(strsplit(classes[classes != ""], ","))), collapse = ","), .groups = "drop") |>
          as.data.frame(), row.names = FALSE)
  cat("ALL events:", sum(r$flagged), "of", nrow(r), "event-districts flagged; expected by chance",
      round(sum(r$ref_flag_share), 1), "| floods only:", sum(r$flagged[r$type == "flood"]), "of", sum(r$type == "flood"),
      "| obs/exp median", round(median(r$obs_exp), 2), "\n")
}
