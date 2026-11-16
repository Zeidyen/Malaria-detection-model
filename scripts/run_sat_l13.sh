#!/bin/zsh
# Monthly refits 2018-2025 of sat-all with climate lags 1-3 only (SATLAG0=0), 4 at a time.
cd "$(dirname "$0")/.."
for y in {2018..2025}; do for m in {1..12}; do
  [ -f out/monthly/model_sat-all-l13_${y}_$(printf %02d $m)_pred.csv ] || echo "$y $m"
done; done | xargs -P 4 -L 1 zsh -c 'SATLAG0=0 SAT=all Rscript scripts/07_model.R $0 sat $1 > out/logs/07_sat-all-l13_monthly_$0_$1.log 2>&1'
echo "=== DONE $(date)"
