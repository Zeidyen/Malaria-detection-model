# Finds failed monthly fits of a model and lists them for an INLA_SAFE refit (DESIGN.md s9 item 9:
# two AR1 months failed silently, with ~100% coverage and CRPS 50-100x normal).
# Usage: Rscript scripts/16_check_fits.R sat-all [sat-rain ...]
# A month is failed if its file is missing, or its zone-adjusted CRPS is more than twice that of
# the same month in the main model (arm), or its log has an INLA error.
# Output: lines "<groups> <year> <month>" on stdout, ready for the INLA_SAFE rerun.
for (lab in commandArgs(TRUE)) for (y in 2018:2025) for (m in 1:12) {
  f <- sprintf("out/monthly/model_%s_%d_%02d_pred.csv", lab, y, m)
  log <- sprintf("out/logs/07_%s_monthly_%d_%d.log", lab, y, m)
  bad <- !file.exists(f)
  if (!bad) {
    ref <- read.csv(sprintf("out/monthly/model_ar_%d_%02d_pred.csv", y, m))
    bad <- mean(read.csv(f)$crps_adj) > 2 * mean(ref$crps_adj)
  }
  if (!bad && file.exists(log)) bad <- any(grepl("^Error|inla.core|crashed", readLines(log)))
  if (bad) cat(paste(gsub("-", ",", sub("^sat-", "", lab)), y, m), "\n", sep = "")
}
