#!/bin/zsh
# Progress of the Earth Engine extraction. Usage (project folder): zsh scripts/gee_status.sh
setopt nullglob
cd "$(dirname "$0")/.."
echo "Year-files done per layer (11 = complete, 2015-2025):"
for l in dynworld chirps era5 lst veg imerg smap viirs gsw; do
  f=(data/derived/gee/${l}_*.csv); printf "  %-9s %2d/11\n" $l ${#f}
done
last=$(ls -t data/derived/gee/*.csv | head -1)
age=$(( ($(date +%s) - $(stat -f %m "$last")) / 60 ))
echo "Latest file: $(basename $last), $age min ago"
if pgrep -f 03_gee_extract >/dev/null; then
  echo "Process: running"
  [ $age -gt 20 ] && echo "WARNING: no new file for $age min - probably stuck; restart it"
else
  echo "Process: NOT running (finished or crashed - see out/logs/03_gee_run2.log)"
fi
echo "Now working on: $(grep -E '^[a-z0-9]+ [0-9]{4} [0-9]+$' out/logs/03_gee_run2.log | tail -1)"
