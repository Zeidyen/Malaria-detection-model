# Load target-year predictions for a model, 2018-2025.
#   "base" : yearly fits, linear district trend (07_model.R SPEC base)
#   "arm"  : monthly-updated fits with the district x year AR1 (07_model.R SPEC ar MONTH),
#            the main model from 2026-10-27
#   "sat-<groups>" : as arm plus satellite covariates (07_model.R SPEC sat), e.g. "sat-all"
load_preds <- function(model) {
  if (model == "base") {
    return(dplyr::bind_rows(lapply(2018:2025, function(y) read.csv(sprintf("out/model_base_%d_pred.csv", y)))))
  }
  if (model == "arm") {
    f <- sprintf("out/monthly/model_ar_%d_%02d_pred.csv", rep(2018:2025, each = 12), rep(1:12, 8))
    miss <- f[!file.exists(f)]
    if (length(miss)) stop(length(miss), " monthly prediction files missing, e.g. ", miss[1])
    return(dplyr::bind_rows(lapply(f, read.csv)))
  }
  if (startsWith(model, "sat-")) {   # monthly AR1 + satellite groups (07_model.R SPEC sat)
    f <- sprintf("out/monthly/model_%s_%d_%02d_pred.csv", model, rep(2018:2025, each = 12), rep(1:12, 8))
    miss <- f[!file.exists(f)]
    if (length(miss)) stop(length(miss), " monthly prediction files missing, e.g. ", miss[1])
    return(dplyr::bind_rows(lapply(f, read.csv)))
  }
  stop("unknown model ", model)
}
