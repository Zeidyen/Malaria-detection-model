# Tier 3 of the alert (DESIGN.md s9 item 6): is a flagged district-month more consistent with
# a TRANSMISSION rise or a REPORTING / care-seeking change?
#
# Reference = the same district and calendar month over the previous NREF years.
#   pm_ratio : malaria's share of all OPD visits (conf / allout), now vs reference. In an
#              outbreak, malaria visits rise faster than other visits, so the share rises. When
#              more facilities report, or care-seeking rises, everything scales and the share
#              stays flat.
#   dtpr     : test positivity (conf / tests), now minus reference. An outbreak raises it (or at
#              least does not lower it). Wider testing of low-risk fevers lowers it.
# Classes:
#   transmission  pm_ratio >= PM_T and dtpr >= -TPR_T
#   reporting     pm_ratio <  PM_R, or dtpr < -TPR_T
#   indeterminate otherwise, or when attendance / tests are implausible (data error)
# The default thresholds are starting values. They are calibrated on synthetic outbreaks and
# reporting artefacts in 09_synthetic.R.
TIER3 <- list(PM_T = 1.2, PM_R = 1.1, TPR_T = 0.02, NREF = 3)

tier3_reference <- function(cases, nref = TIER3$NREF) {
  # cases: data/derived/cases_district_month.csv. Returns unit, year, m and reference sums over
  # years (year - nref) .. (year - 1), same calendar month.
  x <- cases |> dplyr::mutate(allout = allout_u5 + allout_5_14 + allout_ov15,
                              test = test_u5 + test_5_14 + test_ov15) |>
    dplyr::select(unit, year, m, conf_tot, allout, test)
  ref <- lapply(seq_len(nref), function(k) dplyr::mutate(x, year = year + k))
  dplyr::bind_rows(ref) |> dplyr::group_by(unit, year, m) |>
    dplyr::summarise(conf_ref = sum(conf_tot), allout_ref = sum(allout), test_ref = sum(test),
                     nref = dplyr::n(), .groups = "drop")
}

tier3_classify <- function(conf, allout, test, conf_ref, allout_ref, test_ref, th = TIER3) {
  bad <- is.na(allout) | allout <= 0 | conf > allout | is.na(allout_ref) | allout_ref <= 0 |
         test <= 0 | test_ref <= 0
  pm_ratio <- (conf / allout) / (conf_ref / allout_ref)
  dtpr <- pmin(conf / test, 1) - pmin(conf_ref / test_ref, 1)
  cls <- ifelse(pm_ratio >= th$PM_T & dtpr >= -th$TPR_T, "transmission",
         ifelse(pm_ratio < th$PM_R | dtpr < -th$TPR_T, "reporting", "indeterminate"))
  cls[bad] <- "indeterminate"
  data.frame(pm_ratio = pm_ratio, dtpr = dtpr, tier3 = cls)
}
