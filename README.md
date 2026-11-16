# Early detection of malaria upsurges in Ghana

Code and analysis for a national early-detection system for malaria upsurges at district-month level
in Ghana, 2015-2025. Expected confirmed cases are estimated from routine surveillance (DHIMS2) with a
negative binomial R-INLA model (zone seasonality, BYM2 district effects, district-year AR1, and lagged
satellite and climate covariates). The model is refitted every month on earlier data only. A district
is flagged when its observed cases exceed a zone-adjusted 95% prediction limit, and each alert is
classed as a likely transmission increase or a likely reporting change.

Design decisions, the order in which they were made and every intermediate result are recorded in
[DESIGN.md](DESIGN.md).

## Data

| Data | Source | In this repository |
|---|---|---|
| Monthly malaria cases by district, 2015-2025 | DHIMS2, Ghana Health Service | **No.** Available from the Ghana Health Service on request |
| Rainfall, temperature, humidity, soil moisture, NDVI, land cover, night lights | Google Earth Engine (CHIRPS, ERA5-Land, MODIS, SMAP, Dynamic World, VIIRS, WorldPop) | Yes: `data/derived/satellite_district_month.csv` |
| District boundaries | geoBoundaries ADM2, matched to DHIMS2 districts | Yes: `data/derived/units.gpkg` |
| Interventions (nets, SMC, IRS) | Programme reports, PMI, published papers | Yes: `data/derived/interventions_district_year.csv`, `irs_insecticide_cole2026.csv` |
| Documented floods and press reports, 2018-2025 | News, IFRC, NADMO, Ghana Health Service | Yes: `data/derived/real_events.csv` |

Outputs that contain district-month case counts or predictions are not included. `out/` holds the
summary results (detection rates, bootstrap intervals, exposure-response estimates, intervention and
seasonality analyses) and `out/figures/` the figures.

## Running

Run every script from the project folder. R scripts: `Rscript scripts/NN_name.R`; Python scripts:
`python3 -I scripts/NN_name.py` (scripts that call Earth Engine are run without `-I`). With the case
data placed at `data/raw/dhims_national_2015_2025.csv`:

| Step | Scripts |
|---|---|
| Case data and analysis units | `01_cases_qa.R`, `01b_imputation_check.R`, `02_units.R` |
| Satellite and climate data (needs an Earth Engine account) | `03_gee_extract.py`, `15_satellite_panel.R` |
| Interventions | `04_interventions.py` |
| Baseline and expected-cases model, monthly refits | `05_baseline.R`, `06_zone_adjust.R`, `07_model.R`, `run_sat_monthly.sh`, `run_sat_l13.sh`, `16_check_fits.R` |
| Alerts and likely cause | `lib_preds.R`, `lib_tier3.R`, `08_tier3.R`, `14_cusum.R` |
| Simulated upsurges and comparators | `09_synthetic.R`, `11_farrington.R`, `12_consensus.py`, `13_compare.py`, `23_clustered.R` |
| Value of satellite data | `17_satellite_value.R`, `20_bootstrap.R` |
| Documented events, interventions, mining | `21_real_events.R`, `29_interventions_alerts.R`, `22_galamsey.R`, `32_galamsey_s2_districts.py` |
| Climate associations and seasonality | `27_exposure_response.R`, `33_seasonality_climate.R` |
| Figures and dashboard | `10_figures.py`, `18_satellite_figures.py`, `19_satellite_rasters.py`, `25_paper_figures.py`, `28_exposure_figures.py`, `34_seasonality_figure.py`, `35_seasonality_all_vars.py`, `24_dashboard.py` |

Monthly refitting of a model takes several hours (96 fits). Figures are never overwritten: a new
version is saved as `_v2`, `_v3`, and so on.

## Software

R 4.5 with INLA, dlnm, surveillance, sf, dplyr, tidyr, sandwich and lmtest. Python 3 with pandas,
numpy, matplotlib, geopandas, scikit-learn and earthengine-api.
