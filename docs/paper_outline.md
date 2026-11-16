# Paper outline

Draft 2026-10-30. Standalone paper. Numbers are from DESIGN.md s9; the source script is given for each.

**Working title.** Early detection of malaria upsurges in a high-burden endemic setting: a national
district-month system for Ghana using routine surveillance, satellite and climate data, 2015-2025

**Target journal (decided 2026-10-30).** Malaria Journal; fallback BMJ Global Health.

**One-sentence message.** A monthly-updated expected-cases model with satellite and climate layers
finds district-level malaria upsurges in Ghana's routine data at about five alerts a month nationally.
It detects more than published comparators at the same false-alert rate. A simple check separates
likely transmission rises from reporting changes.

---

## Abstract (structured, ~300 words; write last)

Background / Methods / Findings / Interpretation.
Headline numbers:
- +50% one-month upsurges: 43% detected at a 2% false-alert rate, against 30% without satellite data.
- Doubling: 88% / 97%.
- CRPS 215 vs 237.
- Comparators: consensus detector 17%, Farrington 27% (the latter at 3% false alerts).

## 1. Introduction (~700 words)

1. Malaria in Ghana is high-burden and seasonal; it is endemic, not epidemic. Why unusual
   increases still matter:
   - commodity allocation follows expected cases;
   - an increase can be an early sign of intervention failure (ITN, SMC, IRS);
   - floods and new habitat (Bagre spillage, galamsey);
   - data-quality changes.
2. WHO epidemic-detection guidance targets highland and desert-fringe settings. Endemic settings
   need a baseline that moves with season, place and trend.
3. Existing work:
   - risk maps (MAP, Aheto 2022);
   - climate-based early warning, mostly highland or East Africa;
   - DHIMS2 anomaly detection (Ansah-Narh & Asare Afrane 2026): no covariates, no denominator,
     the baseline includes the month being judged, and region-level patterns.
   - Use docs/literature_review.md.
4. Gap and aims:
   - (i) build and validate a prospective district-month system;
   - (ii) measure what satellite and climate data add at a fixed false-alert rate;
   - (iii) separate transmission from reporting;
   - (iv) secondary: surface mining.

## 2. Methods

### 2.1 Data
- **DHIMS2 national extract.** 247 analysis units, monthly 2015-2025: confirmed cases, all-OPD
  visits and tests. Unit harmonisation (the Guan merge and others). QA and the imputation check go
  in the appendix (01, 01b, 02).
- **WorldPop population.**
- **Satellite and climate layers through Earth Engine** (03, 15). Table 1 lists each product,
  resolution, aggregation (population-weighted vs area share) and gap handling:
  - CHIRPS, MODIS LST day/night, MODIS NDVI, SMAP, ERA5-Land t2m/RH, Dynamic World (previous year),
    VIIRS.
  - ERA5 is reanalysis; say so.

### 2.2 Expected-cases model (07)
- Negative binomial, R-INLA, offset log population:
  - cyclic RW2 season per ecological zone;
  - BYM2 district effect;
  - IID year effect;
  - district × year AR1.
- Satellite version: DLNM cross-basis terms, lags 0-3 (ns df 2 × 2), for rain, LST, soil moisture,
  NDVI and ERA5, plus linear land-cover and night-light terms.
- **Prospective:** refitted every month on all data up to M-1, giving 96 fits per model for 2018-2025.
- Failed fits are detected (16) and refitted with the Gaussian approximation; report how many.
- Why the AR1 and not a linear trend: urban reporting jumps in 2019-21 (s9 item 9).
- Interventions tested and omitted; reported as a sensitivity analysis (s9 item 7).

### 2.3 Alert rule (06, 08)
- Zone adjustment: observed / expected for the other districts in the same zone and month
  (leave-one-out). It removes system-wide shifts and is available in real time.
- Alert: observed above the adjusted upper 95% limit, one month (z > 1.96).
- CUSUM was tested and not adopted (14); mention briefly.
- **Likely-cause check** (Tier 3 in the code): malaria share of OPD visits vs the same month in the
  previous 3 years (PM_T 1.2), and the change in test positivity (TPR_T 0.02). Gives transmission /
  reporting / unclear. Thresholds are calibrated on synthetic events.

### 2.4 Validation
1. **Prediction skill:** CRPS, 95% coverage, PIT, by year.
2. **Synthetic upsurges** (09): 12,000 injected events.
   - Sizes +25 / 50 / 100%; durations 1 and 3 months; transmission upsurges and reporting artefacts.
   - Sensitivity at a FIXED 2% false-alert rate (threshold grid, interpolation; 17).
3. **Comparators on the same injections:**
   - Farrington flexible (11);
   - the consensus detector of Ansah-Narh & Asare Afrane, made prospective and district-level (12);
   - all compared at matched false-alert rates (13).
4. **Satellite value:** sat-all and one layer group at a time vs no satellite. Paired district
   bootstrap, B = 2000 (20).
5. **Robustness:**
   - lags 1-3 only, i.e. no same-month satellite data (real-time availability). See Results 3.3.
   - clustered upsurges in 1-20 neighbouring districts (23).
6. **Documented events** (21): 14 floods and press reports, 57 event-districts. Expected flags from
   the same districts and calendar months in other years. Framed as a plausibility check.

### 2.5 Secondary analysis: surface mining (22)
- Pre-specified before extraction (DESIGN s6b). Exposure is the 2016-24 Dynamic World bare-ground
  increase in 116 forest-belt districts, using the top quartile (29).
- Tests T1 and T2. T2 is adapted; say why.
- Exploratory incidence models, labelled as not pre-specified.
- Stricter exposure definition (14 districts) and rainfall control.

## 3. Results

### 3.1 Data and model fit
- National series by zone: fig1.
- Skill, sat-all vs arm vs the linear-trend baseline: CRPS 215 / 237 / 363; coverage; flag rate.
  Fig: CRPS by year.
- District examples: fig2 (Tema, Krowor, Ayawaso Central, Kumasi, Yunyoo-Nasuan, Amansie West).

### 3.2 Detection of synthetic upsurges
- Table 2, sensitivity at 2% false alerts, sat-all vs arm, with bootstrap intervals (out/bootstrap_arm_vs_sat-all.csv):

  | Size | 1 month | 3 months |
  |---|---|---|
  | +25% | 13 (gain +3.9) | 25 (gain +6.3) |
  | +50% | 43 (gain +12.4) | 70 (gain +16.0) |
  | doubling | 88 (gain +8.8) | 97 (gain +2.4) |

- Operating points (threshold vs false alerts vs sensitivity). Tie this to alerts per month
  nationally: 2% ≈ 5 alerts.
- Fig4 (sensitivity curves).

### 3.3 What the satellite layers add
- Layer table and fig12. ERA5 and NDVI carry most of the gain; rain is modest; soil moisture and
  land cover add about 0.
- Lags 1-3 only (no same-month satellite data): the gain is unchanged. +50% 43 / 70, doubling 86 / 97,
  CRPS 215; gain over arm +12.8 (8.0, 16.2) at +50% 1 month. vs sat-all: no difference except doubling
  1 month (+1.5 points for lag 0). The signal comes from the previous 1-3 months.
- Satellite maps and pixel layers (fig8-11, fig13) go in the supplement, apart from one main-text
  panel.

### 3.4 Comparison with existing methods
- Fig7 / Table 3 at matched false-alert rates.
- Published settings: the consensus detector flags 14.5% of months and Farrington 19.2%.

### 3.5 Likely cause of alerts
- Real alerts 2018-25 (415): 42% transmission, 51% reporting, 7% unclear.
- Synthetic: balanced accuracy 0.80. Fig5.
- 2021 urban case study: Tema and Krowor transmission vs Ayawaso Central and Kumasi reporting.
- Fig6: map of the alert share.

### 3.6 Clustered upsurges
- Size dependence table. The zone adjustment cancels widespread rises (27 vs 37 at 20 districts),
  and the either-rule is robust. Leads into the zone-wide signal in the Discussion.

### 3.7 Documented events
- sat-all 9 of 57 vs 3.9 expected (P = 0.017); arm 9 vs 7.4 (P = 0.33).
- Anloga ×1.79 is flagged but classed as reporting. North Tongu ran below expected.

### 3.8 Surface mining
- The pre-specified tests are null. Exploratory: +2.8% per point bare+water, +8.7% per point
  Sentinel-1 water. Mining/other incidence ratio 1.32 → 1.64. Fig14, fig15.

## 4. Discussion (~1,200 words)
1. Main findings in plain terms.
2. Why satellite data help: temperature, humidity and vegetation explain month-to-month departures
   the AR1 cannot anticipate. Rain alone does little; slow layers are absorbed by the district
   effects.
3. Comparison with Ansah-Narh & Asare Afrane and with highland early-warning work.
4. The likely-cause check: neither comparator can do this. Urban reporting changes are common, and
   telling them apart matters for the response.
5. The system is built to absorb slow change. Galamsey shows the trade-off: a detection system
   treats a slow rise as the new normal. Trend monitoring is a separate task.
6. Operational path:
   - monthly DHIMS2 export plus GEE;
   - about 5 alerts a month;
   - a zone-wide signal for widespread rises;
   - prototype dashboard (Supplementary File).
7. Limitations:
   - upstream imputation of unknown method;
   - no refit after injection (months 2-3 slightly optimistic);
   - synthetic upsurges are multiplicative copies of observed cases;
   - few documented events;
   - Dynamic World drift between years;
   - ERA5 is reanalysis;
   - the likely-cause thresholds are set on synthetic data;
   - the comparators were adapted;
   - intervention data are coarse.
8. Conclusion.

## Supplement
- S1 data QA and the imputation check; unit harmonisation table.
- S2 satellite extraction details, gap filling, maps (fig8-11, fig13).
- S3 model specification, priors, failed-fit handling.
- S4 CUSUM, intervention model, single-layer bootstrap table.
- S5 comparator adaptations.
- S6 real-event list with sources (docs/real_events_sources.md).
- S7 galamsey exposure table and all models.
- **Supplementary File: prototype dashboard (HTML).** Needs a decision on DHIMS2 counts vs
  ratios only.

## Declarations the user must supply
- DHIMS2 data access / permission statement (Ghana Health Service).
- Ethics: secondary aggregated data; GHS-ERC exemption or approval.
- Data availability: satellite data and code public; DHIMS2 on request to GHS.
- Funding, competing interests, author contributions.
