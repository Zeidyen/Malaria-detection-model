#!/bin/zsh
# Runs the extraction (layers from $LAYERS, default the main nine), restarting it after a crash (finished files are skipped). Up to 20 attempts.
cd "$(dirname "$0")/.."
for i in $(seq 1 20); do
  echo "=== attempt $i $(date)"
  python3 -u scripts/03_gee_extract.py --project durable-circle-448314-t3 \
    --layers ${LAYERS:-dynworld,chirps,era5,lst,veg,imerg,smap,viirs,gsw} --years 2015-2025 && { echo "=== DONE $(date)"; exit 0; }
  sleep 60
done
echo "=== GAVE UP after 20 attempts $(date)"
