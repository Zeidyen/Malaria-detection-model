# Synthetic-event validation of the alert system (DESIGN.md s6).
# Usage: Rscript scripts/09_synthetic.R [MODEL=arm]   (see scripts/lib_preds.R)
# Events are injected into the REAL target-period data, 2018-2025. Each prediction is fitted
# only on data before the predicted month (monthly model) or year (yearly model), so an injection
# does not change that month's predictive distribution; only the zone-month leave-one-out ratio
# is recomputed. No refitting is needed. LIMITATION for the monthly model: in a real system the
# months after an event's first month would be predicted from data that already include the
# event, so the model would partly adapt. Ignoring this makes detection in months 2-3 of a
# 3-month event somewhat optimistic; detection in the first month is unaffected. The adjusted upper limit is the raw 95% limit times R_loo; this is exact
# because rescaling the draws by a positive constant rescales their quantiles.
#
# Event types (k = size multiplier, L = duration in months):
#   outbreak : extra cases ~ Poisson((k - 1) * observed). Each extra case is also an OPD visit
#              and a positive test, so malaria's share of visits and test positivity both rise.
#   artefact : cases, tests and OPD attendance are all multiplied by k (more facilities
#              reporting, or a care-seeking rise); shares and positivity are unchanged.
# For each type x k x L, year and replicate: NEV random districts get one event each, starting
# in a random month.
# Metrics:
#   sensitivity  share of events with at least one flag in the event months (also shown net of
#                the background flag rate in the same months without injection)
#   delay        months from event start to first flag, among detected events
#   false alerts flag rate in district-months with no injected event
#   tier3        class given to detected events (outbreaks should be "transmission", artefacts
#                "reporting"); then the Tier 3 thresholds are calibrated on these labels.
# Output: out/synthetic_events_<MODEL>.csv, out/synthetic_summary_<MODEL>.csv,
#         out/tier3_calibration_<MODEL>.csv, out/synthetic_injections_<MODEL>.csv (every injected
#         district-month with its new values, so comparator methods are scored on the SAME events)
suppressMessages(library(dplyr))
source("scripts/lib_tier3.R"); source("scripts/lib_preds.R")
MODEL <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[1] else "arm"
set.seed(20261028)
NREP <- 5; NEV <- 25
GRID <- expand.grid(type = c("outbreak", "artefact"), k = c(1.25, 1.5, 2), L = c(1, 3),
                    stringsAsFactors = FALSE)

cases <- read.csv("data/derived/cases_district_month.csv")
ref <- tier3_reference(cases)
now <- cases |> transmute(unit, year, m, allout = allout_u5 + allout_5_14 + allout_ov15,
                          test = test_u5 + test_5_14 + test_ov15)
P <- load_preds(MODEL) |>
  select(unit, zone, year, m, conf_tot, pred_med, hi95) |>
  left_join(now, by = c("unit", "year", "m")) |> left_join(ref, by = c("unit", "year", "m"))

flag_adj <- function(x) {
  key <- paste(x$zone, x$m)
  to <- ave(x$conf, key, FUN = sum); tp <- ave(x$pred_med, key, FUN = sum)
  x$conf > x$hi95 * (to - x$conf) / (tp - x$pred_med)
}

ev <- list(); bg <- list(); injl <- list(); id <- 0
for (g in seq_len(nrow(GRID))) {
  type <- GRID$type[g]; k <- GRID$k[g]; L <- GRID$L[g]
  for (y in 2018:2025) {
    base <- P[P$year == y, ] |> mutate(conf = conf_tot)
    f0 <- flag_adj(base)
    for (r in seq_len(NREP)) {
      x <- base
      units <- sample(unique(x$unit), NEV)
      starts <- sample(1:(13 - L), NEV, replace = TRUE)
      inj <- rep(FALSE, nrow(x)); evid <- rep(NA_integer_, nrow(x))
      for (j in seq_len(NEV)) {
        rows <- which(x$unit == units[j] & x$m >= starts[j] & x$m < starts[j] + L)
        id <- id + 1; inj[rows] <- TRUE; evid[rows] <- id
        if (type == "outbreak") {
          extra <- rpois(length(rows), (k - 1) * x$conf[rows])
          x$conf[rows] <- x$conf[rows] + extra
          x$allout[rows] <- x$allout[rows] + extra
          x$test[rows] <- x$test[rows] + extra
        } else {
          x$conf[rows] <- round(x$conf[rows] * k)
          x$allout[rows] <- round(x$allout[rows] * k)
          x$test[rows] <- round(x$test[rows] * k)
        }
      }
      injl[[length(injl) + 1]] <- data.frame(type = type, k = k, L = L, year = y, rep = r,
        evid = evid[inj], unit = x$unit[inj], m = x$m[inj], conf = x$conf[inj],
        allout = x$allout[inj], test = x$test[inj])
      fl <- flag_adj(x)
      t3 <- with(x, tier3_classify(conf, allout, test, conf_ref, allout_ref, test_ref))
      e <- data.frame(evid = evid, m = x$m, flag = fl, flag0 = f0, pm_ratio = t3$pm_ratio,
                      dtpr = t3$dtpr, tier3 = t3$tier3)[inj, ] |>
        group_by(evid) |> arrange(m, .by_group = TRUE) |>
        summarise(detected = any(flag), detected0 = any(flag0),
                  delay = if (any(flag)) which(flag)[1] - 1 else NA_real_,
                  pm_ratio = if (any(flag)) pm_ratio[which(flag)[1]] else NA_real_,
                  dtpr = if (any(flag)) dtpr[which(flag)[1]] else NA_real_,
                  tier3 = if (any(flag)) tier3[which(flag)[1]] else NA_character_, .groups = "drop") |>
        mutate(type = type, k = k, L = L, year = y, rep = r)
      ev[[length(ev) + 1]] <- e
      bg[[length(bg) + 1]] <- data.frame(type = type, k = k, L = L, year = y, rep = r,
                                         false_rate = mean(fl[!inj]))
    }
  }
}
ev <- bind_rows(ev); bg <- bind_rows(bg)
write.csv(ev, sprintf("out/synthetic_events_%s.csv", MODEL), row.names = FALSE)
write.csv(bind_rows(injl), sprintf("out/synthetic_injections_%s.csv", MODEL), row.names = FALSE)

S <- ev |> group_by(type, k, L) |>
  summarise(events = n(), sensitivity = mean(detected), background = mean(detected0),
            net_sensitivity = mean(detected) - mean(detected0),
            median_delay = median(delay, na.rm = TRUE),
            tier3_transmission = mean(tier3 == "transmission", na.rm = TRUE),
            tier3_reporting = mean(tier3 == "reporting", na.rm = TRUE), .groups = "drop") |>
  left_join(bg |> group_by(type, k, L) |> summarise(false_alert_rate = mean(false_rate), .groups = "drop"),
            by = c("type", "k", "L"))
write.csv(S, sprintf("out/synthetic_summary_%s.csv", MODEL), row.names = FALSE)
cat("Synthetic events:", nrow(ev), "\n\n")
print(S |> mutate(across(where(is.double) & !c(k, L), ~ round(.x, 3))) |> as.data.frame(), row.names = FALSE)

# ---- Tier 3 threshold calibration ---------------------------------------------------------
# Labels: outbreak -> transmission, artefact -> reporting, among detected events. Score =
# balanced accuracy (mean of the two correct-class rates); indeterminate counts as wrong.
det <- ev |> filter(detected)
cal <- expand.grid(PM_T = c(1.05, 1.1, 1.15, 1.2, 1.3), TPR_T = c(0.01, 0.02, 0.05)) |>
  rowwise() |> mutate(
    acc_outbreak = mean(with(det[det$type == "outbreak", ],
      ifelse(pm_ratio >= PM_T & dtpr >= -TPR_T, "transmission", "x")) == "transmission", na.rm = TRUE),
    acc_artefact = mean(with(det[det$type == "artefact", ],
      ifelse(pm_ratio >= PM_T & dtpr >= -TPR_T, "x",
      ifelse(pm_ratio < PM_T | dtpr < -TPR_T, "reporting", "x"))) == "reporting", na.rm = TRUE),
    balanced = (acc_outbreak + acc_artefact) / 2) |> ungroup() |> arrange(desc(balanced))
write.csv(cal, sprintf("out/tier3_calibration_%s.csv", MODEL), row.names = FALSE)
cat("\nTier 3 calibration (PM_R set equal to PM_T, so no indeterminate band; top 6):\n")
print(head(as.data.frame(cal |> mutate(across(where(is.double), ~ round(.x, 3)))), 6), row.names = FALSE)
