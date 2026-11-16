#!/bin/zsh
# Monthly refits 2018-2025 of SPEC sat for each satellite group set given (07_model.R), 4 at a time.
# Usage: zsh scripts/run_sat_monthly.sh all rain lst sm ndvi era5 env
# A month whose output already exists is skipped. Failed fits are found and refitted with
# INLA_SAFE=1 afterwards by scripts/16_check_fits.R.
cd "$(dirname "$0")/.."
for g in "$@"; do for y in {2018..2025}; do for m in {1..12}; do
  f=out/monthly/model_sat-${g//,/-}_${y}_$(printf %02d $m)_pred.csv
  [ -f $f ] || echo "$g $y $m"
done; done; done |
xargs -P 4 -L 1 zsh -c 'SAT=$0 Rscript scripts/07_model.R $1 sat $2 > out/logs/07_sat-${0//,/-}_monthly_$1_$2.log 2>&1'
echo "=== DONE $(date)"
