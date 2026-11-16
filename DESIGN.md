# Ghana malaria detection system: design note

Draft 2026-10-27. National scope. Nothing built yet.

**Terminology (decided 2026-10-30).** Malaria in Ghana is endemic with seasonal peaks, not
epidemic in the classic sense (WHO epidemic guidance targets highland and desert-fringe settings).
The paper therefore says **malaria upsurge** / **unusual increase** (a district running well above
its expected level for the time of year), not "outbreak", and frames the system as **early warning of
unusual increases in a high-burden endemic setting**. Injected events are "transmission upsurges"
(code label `outbreak`) and "reporting artefacts" (code label `artefact`); the code labels are kept
so earlier outputs stay readable. "Tier 3" is called the **likely-cause check** in the paper, figures and dashboard (classes: transmission / reporting / unclear; code label `tier3`, `indeterminate`). Why upsurges matter here: commodity stock-outs (RDT/ACT allocation
follows expected cases), early sign of intervention failure (nets, SMC, IRS), floods and new habitat
(Bagre dam spillage, galamsey), and data-quality changes (Tier 3). Older notes below still say
"outbreak"; read it as upsurge.

## 1. The question

For every district and month in Ghana, how many malaria cases would we expect given
climate, environment (from satellite data), population and interventions? When do the
observed cases depart far enough from that to flag?

The product is an **expected-cases baseline plus an alert rule**, validated out of sample.
It is not a forecast of future months, and it is not a risk map in its own right. Risk maps
with covariates already exist (Aheto 2022, MAP).

## 2. Why this is new

Closest work: Ansah-Narh & Asare Afrane, arXiv:2607.21559 (July 2026), consensus
unsupervised anomaly detection on DHIMS2 malaria admissions, 2014-2023.

| Their limitation | Source | This study |
|---|---|---|
| No climate, environment or intervention covariates | their limitation 3 | Satellite climate + environment layers, SMC and ITN terms |
| Baseline uses all 10 years, including the month being judged | their limitation 5, Eq. 2 | Rolling origin: each year is judged only on earlier years |
| Counts, no population denominator | Eq. 1-3 | Rates: WorldPop offset |
| No spatial dependence | their limitation 4 | District BYM2 spatial random effect |
| Raw case totals are features, so big regions look anomalous | Table 1, d = 3.25 on totals | Departures are measured against each district's own expected rate |
| Anomaly share fixed at 10% for every detector | Section 2.3 | Alert threshold set from prediction intervals, then tuned on simulated outbreaks |
| Validated only by showing flagged months differ on the features that flagged them | Section 3.4 | Synthetic outbreaks injected into real data: sensitivity, false alerts, timeliness |
| District anomaly counts identical within a region (37 / 46 / 11) | Fig. 11 | Detection at district level |

Their method is the main comparator. We reimplement it on our data (Section 6).

## 3. Data

### 3.1 Cases

**Update 2026-10-27: a national district-month extract was already on disk**, so it is the
primary dataset and the under-5 facility file becomes secondary.

| Source | Coverage | Content | Role |
|---|---|---|---|
| `smc-regimen-delivery/geo/data/raw/dhims/dhims_national_2015_2025.csv` (Zeid's DHIMS2 extract, 9 Oct 2026) | 16 regions, 248 districts, monthly 2015-2025 | All OPD, suspected, tested, confirmed by age (u5, 5-14, 15+), population | **Primary dataset** |
| `~/Downloads/Malaria under5 (2012-2022).xlsx` | 261 districts, facility level, 2012-2022 | OPD malaria, under 5 | Secondary: 2012-14 extension, facility-level reporting checks |

Built so far (`scripts/01_cases_qa.R`, `scripts/02_units.R`):
- **247 analysis units.** DHIMS uses an older district list than geoBoundaries (260 polygons).
  Kumasi covers 6 polygons, Accra Metro 8 and Tema 2, so those polygons are merged. 25 spelling
  aliases are mapped explicitly.
- **Guan (Oti) merged into Hohoe.** Guan was split from northern Hohoe Municipal (Volta) on
  8 Oct 2021 and is Ghana's 261st district, so the 260-polygon set has no Guan polygon. Its cases
  and population are added to Hohoe, whose polygon still covers both. No district is dropped.
- **QA.** No NAs, almost no zeros, and only 51 months repeat the previous month exactly, so there is
  no sign of crude carry-forward imputation. But the data are suspiciously complete.
  Zeid confirmed (2026-10-27) that it was cleaned/imputed upstream; method unknown.
  **Imputation check (`scripts/01b_imputation_check.R`): no detectable trace.** Exact
  interpolation midpoints and exact month-to-month repeats occur no more often than near misses
  1-3 counts away (ratio 0.80-1.10 for confirmed cases by age; 1.23-1.30 for suspected under-5,
  about 20 extra months nationally). There are no non-integer values, no mean or median fill, and
  spikes up to 9x the district median are still present, so outliers were not capped. Whatever was
  done left no simple trace in confirmed cases. Still ask the source for the cleaning description,
  and report this test in a data-quality appendix.
- **Tests are unreliable as a denominator.** Confirmed > tested in 2,091 under-5 district-months;
  tested > suspected in 2,000-6,000 per age group. Confirmed cases are the outcome; tests enter
  only as a sensitivity analysis.
- **Extreme months exist.** For example, Yunyoo-Nasuan Jul-Oct 2021-22 reached up to 9x its median.
  These are candidate real events or reporting errors, useful for testing the detector.

Notes on the secondary under-5 file, kept for when it is used:
- **Reporting growth.** Facility count rises from ~3,300 (2012-13) to ~5,600 (2022). Rising
  district totals partly reflect new facilities reporting. Plan: build district series from a
  **stable cohort** (facilities reporting at least 80% of months; threshold to be tested), and
  use the full set as a sensitivity analysis. Facility count goes in as a reporting covariate.
- **Missing reports.** 14-27% of facility-months are blank, depending on the sheet. Treat a blank
  as missing, not zero. Impute within the facility, or drop it from the cohort.
- **Indicator ambiguity.** "OPD malaria cases": not yet known whether this is confirmed only or
  includes clinical (untested) diagnoses. Check against the northern panel where both exist.
- **Layout varies by sheet.** Some sheets hold two years each, and the 2020/2021 sheets have
  extra columns. The `reshape` sheets look like an earlier long-format conversion. Verify they
  match the wide sheets before trusting them. Paired years have identical row counts
  (2012=2013, 2015=2016, 2017=2018), which should be checked for duplicated values.
- **District boundary changes.** Regions split in 2019 (10 → 16) and districts were re-created in
  2012, 2018 and 2019. Map every facility to one fixed 261-district boundary set.
- **Under-5 only, ending 2022.** SMC suppresses under-5 cases in the north from June to October,
  so the SMC term is essential, not optional.

### 3.2 Satellite and environmental layers

All aggregated to district-month, **weighted by WorldPop population**, so that values reflect
where people live, not the empty parts of the district.

| Variable | Product | Resolution | Why it matters for malaria |
|---|---|---|---|
| Rainfall | CHIRPS v2 (already downloaded 2014-2025) | 5 km, monthly | Breeding sites; lag 1-2 months found in the SMC work |
| Rainfall (sensitivity) | GPM IMERG | 10 km, monthly | Second rainfall estimate, to test robustness |
| Land surface temperature, day and night | MODIS MOD11A2 / MYD11A2 | 1 km, 8-day | Parasite and mosquito development; night LST tracks minimum temperature |
| Vegetation | MODIS MOD13A3 NDVI / EVI | 1 km, monthly | Proxy for humidity and vegetation; captures the dry-season green-up near water |
| Soil moisture | SMAP L4 (2015-) or ESA CCI (full period) | 9-25 km, daily | Standing water; persists longer after rain than rainfall itself |
| Surface water | JRC Global Surface Water monthly history (Landsat) | 30 m, monthly | Dams, irrigation (Tono, Vea, Bontanga), flooded fields; dry-season transmission |
| Humidity | ERA5-Land (reanalysis, not satellite) | 9 km, hourly | Mosquito survival; satellite products do not measure it well |
| Urbanicity | VIIRS night lights | 500 m, monthly | Urban areas have lower transmission; tracks urban growth over time |
| Elevation | SRTM | 30 m | Static, minor in Ghana; mostly the Kwahu and Volta highlands |
| Land cover | ESA WorldCover / MODIS MCD12Q1 | 10 m / 500 m | Static share of cropland, forest, built-up and wetland |
| Population | WorldPop, annual, by age | 100 m | Denominator, and weights for aggregation |
| Land cover, monthly | Dynamic World V1 (Sentinel-2) | 10 m, per scene → monthly, from Jul 2015 | Time-varying shares of built-up, crops, water, bare ground and **flooded vegetation** (breeding-habitat proxy) |
| Open water through cloud | Sentinel-1 radar (VV < -18 dB) | 10 m → 100 m, 6-12 day revisit | Rainy-season water when optical sensors are blind; threshold checked against JRC GSW 2015-21 |
| People near water | Sentinel-1 water + WorldPop | 100 m | **Share of the population within 2 km of open water** (Anopheles flight range) |
| Water and moisture indices | Sentinel-2 MNDWI, NDMI, Cloud Score+ masked | 10 m → 100 m, from 2017 | Small dams, dugouts and rice fields that 1 km MODIS cannot see |

Added 2026-10-27 after reviewing a land-use/land-cover workflow (StudyHacks GEE tutorial).
We use existing, validated products (Dynamic World) rather than training our own classifier,
because a custom classification would need field data and an accuracy assessment of its own.

**Weighting.** Climate layers are population-weighted. Land-cover and water layers are AREA
shares, because population weighting drops the very pixels (water, bare ground) nobody lives on.
The people-near-water layer then links the two.

Known problem: **cloud cover**. MODIS LST and NDVI have large gaps in the rainy season in southern
Ghana, which is exactly when transmission rises. Use the 8-day composites, report the cloud-gap
share per district-month, and gap-fill by temporal interpolation. Night LST is less affected than
day LST.

Access: Google Earth Engine holds all of these, and one script can produce the whole
district-month table. Alternative without GEE: NASA AppEEARS (needs an Earthdata login) plus
direct downloads. **Decision needed: which route.**

### 3.3 Interventions

- SMC: districts and rounds per year (NMEP); under-5 only, northern regions.
- ITN mass campaigns: year and region (2012, 2014-16, 2018-19, 2021-22 rounds; to confirm).
- IRS: the AngloGold / PMI districts and years.
- RTS,S / R21 vaccine pilot and rollout districts (2019-).
- COVID-19 disruption: an indicator for 2020 months.

## 4. Model: expected cases

Negative binomial spatio-temporal model in R-INLA, at district-month level:

```
cases[d,t] ~ NegBin(mu[d,t], theta)
log mu[d,t] = log(pop_u5[d,t])            # offset: rate per child
            + f_season(month | zone)       # cyclic RW2, separate for the 3 ecological zones
            + crossbasis(climate lags 0-3) # DLNM terms for rainfall, LST, soil moisture, NDVI
            + beta * environment           # TIME-VARYING: Dynamic World shares, radar water,
                                           # people near water, night lights; static: elevation
            + gamma * interventions        # SMC round, ITN campaign, IRS, vaccine
            + delta * log(reporting facilities)
            + u[d] + v[d]                  # BYM2 district spatial effect
            + w[year]                      # year effect
```

Comparators, all fitted the same way:
- **Calendar baseline:** season + district + year only, no climate or satellite data. The full
  model must beat this.
- **Ablation:** add each satellite layer one at a time. This answers directly whether satellite
  data helps, and which layer.
- **GBM (LightGBM)** with the same inputs, to see whether a flexible model adds anything.

Expect the honest finding from the SMC work to recur: climate explains **differences between places**
far better than **differences between years**. The ablation is designed to show this either way.

## 5. Alert rule

- **Rolling origin.** For target year Y, fit on years before Y only, then predict every month of Y.
  First target year 2015 (three years of training).
- A district-month is **flagged** when observed cases exceed the upper 95% (or 99%) prediction limit.
- **Persistent signal:** two consecutive flagged months, a rule the programme can act on.
- **Data-quality flags kept separate.** A spike that coincides with a jump in reporting facilities,
  or (where tests exist) a jump in tests, is labelled a reporting artefact, not transmission.

## 6. Validation

1. **Synthetic outbreaks.** Inject outbreaks into the real series and measure sensitivity, false-alert
   rate and delay to detection. Vary size (+25%, +50%, +100%), duration (1-3 months), season and
   district burden.
2. **Prediction skill** for each held-out year: CRPS, PIT histograms for calibration, and coverage
   of the 95% interval.
3. **Head-to-head comparisons** on identical data and identical synthetic outbreaks:
   - this model
   - Ansah-Narh consensus (Isolation Forest + LOF + autoencoder + Elliptic Envelope, S ≥ 3)
   - Farrington flexible (R `surveillance`)
   - calendar baseline
4. **Known events,** where documented: flood years, SMC rollout, and ITN campaign gaps.

## 6b. Pre-specified secondary analysis: surface mining (galamsey)

Written down before the satellite data are extracted, so it is a test, not a finding after
the fact.

**Hypothesis.** Expansion of artisanal gold mining creates open pits that fill with water,
adding breeding habitat. So in mining districts, growth in bare ground and open water is
followed by excess malaria above the expected baseline.

**Why it is plausible here.** The arXiv paper's highest anomaly rates sit in the Adansi /
Afigya Kwabre cluster of Ashanti. In our QA, Amansie West, July 2024, was among the most extreme
district-months nationally. Both are in mining areas. This motivates the test; it is not evidence.

**Mining exposure, defined without looking at malaria.** Among districts in the forest belt
(Ashanti, Western, Western North, Eastern, Central), mining districts are those in the top
quartile of the 2016-2024 increase in the Dynamic World bare-ground share. The definition is
fixed before any model is fitted. A sensitivity analysis uses an external mining map if one is
available (e.g. Minerals Commission or published galamsey extent maps).

**Tests.**
1. Does a mining-district × year interaction on bare + water share explain residual excess cases
   in the full model?
2. Are anomaly flags more frequent in mining districts after 2016 than before, relative to other
   forest-belt districts (difference in differences)?

**Caveat.** Mining also brings migrant workers with low immunity and poor access to nets. The
effect cannot be attributed to habitat alone.

## 7. Outputs

- District map: share of months flagged, and excess cases.
- Alert table, by district and month.
- Which satellite layers matter: the ablation table.
- A reusable pipeline that updates monthly as new DHIMS2 and satellite data arrive.

## 8. Decisions

Made (2026-10-27): **Google Earth Engine** for satellite data; **standalone paper**.
Made (2026-10-30): **target journal Malaria Journal** (fallback BMJ Global Health); Lancet Planetary Health considered and rejected (detection paper, environment is supporting). Manuscript drafts in `docs/manuscript/`.

Open:
1. **Cleaning description from the data source** (confirmed imputed; method unknown, no trace
   found) and any reporting-completeness column.
2. **Contact Ansah-Narh and Afrane?** Collaborate, or move fast and cite.

## 9. Status and next steps

1. DONE: national case panel, 247 units × 132 months (`data/derived/cases_district_month.csv`,
   `units.gpkg`).
2. READY TO RUN (needs Zeid's Earth Engine login): `scripts/03_gee_extract.py`, which pulls all
   satellite layers as population-weighted district-month means.
3. DONE (2026-10-27): calendar baseline, one rolling step (`scripts/05_baseline.R`; fit on
   2015-22, predict 2023). It is a negative binomial INLA model with zone-specific cyclic season,
   BYM2 district effect and year effect. 95% coverage 0.933, 4.8% flagged, CRPS 445. Without a
   trend term, districts whose level shifted were flagged nearly every month (North-East Gonja
   12/12, Tema 10/12). **Adding a district-specific linear trend is now the default:** CRPS 349
   (-22%), coverage 0.936, 4.8% flagged, and no district flagged more than 7/12. PIT still skews
   high (2023 under-predicted; North over-predicted by 8%). The year effect is the next thing to
   look at.
4. DONE (2026-10-27): district-year intervention table, 247 x 2015-2025
   (`data/derived/interventions_district_year.csv`, built by `scripts/04_interventions.py`;
   citations, coding rules and gaps in `interventions_sources.md`). Public sources only.
   **SMC coding, decided 2026-10-27: `smc_alt` (published evidence) is the MAIN coding.**
   PMI MOPs FY2022-24, GNA (Kadjebi 2023) and the Health Minister's 2025 speech put SMC in
   Bono East and Oti from 2021. The north-only coding (`smc`) is a sensitivity analysis. Gaps: ITN campaign months
   (968 district-years NA), SMC below region level in 2018-21, Bono East SMC district names,
   and vaccine pilot districts read from a published map (to confirm with GHS/EPI).
5. DONE (2026-10-27): rolling baseline for every target year 2018-2025
   (`out/baseline_all_years_pred.csv`). Flags were far from the nominal 5%: 10-11% in 2018, 2019
   and 2021, and 2% in 2020, 2024 and 2025. Cases ran 17-20% above prediction NATIONALLY in
   2018-19, across 11-12 of 16 regions: a system-wide shift, not local outbreaks.
6. FINDING, now part of the design: a THREE-TIER ALERT (`scripts/06_zone_adjust.R`, first version).
   - **Tier 1, zone shift:** observed / predicted for the zone-month as a whole. 52 of 288
     zone-months were off by more than 20% (e.g. Forest, all 12 months of 2018).
   - **Tier 2, district anomaly:** each district judged against the other districts in its zone
     in the same month (leave-one-out ratio). All districts report together, so this works in
     real time. Flags fall to 4.7-4.8% in 2018-19 and rise to about 2.8% in 2024-25.
   - **Tier 3, transmission or reporting:** a flagged district is classed as REPORTING if
     all-OPD attendance and tests rose with malaria and test positivity did not rise, and as
     TRANSMISSION if malaria rose faster than attendance and positivity rose. 2021 is the test
     case: 10 districts were flagged for 9-12 months at 1.1-2.4x the 2020 level. In 8 (Kumasi,
     Ayawaso Central, Sekondi-Takoradi, Eastern districts) attendance and tests rose too and
     positivity fell: reporting or care-seeking. In Tema (malaria +69% while attendance -18%,
     positivity 0.18 -> 0.22) and Krowor (+138% vs +58%, 0.10 -> 0.12), transmission is plausible.
   This separation is a contribution in its own right: the arXiv comparator has neither tests
   nor attendance, so it cannot tell a reporting change from an outbreak.
   To do: move the zone x month term inside the model rather than rescaling quantiles; set the
   Tier 3 rule's thresholds on synthetic outbreaks and data, not by eye.
7. DONE (2026-10-27): intervention terms, `scripts/07_model.R` (SPEC base vs int, 2018-2025; zone
   adjustment now applied to the predictive draws inside the script).
   **Interventions do not improve prediction.** Mean CRPS (zone-adjusted) base 362.9 vs int 365.8
   (+0.8%); worse in 2018 (+4.9%, little history), and within +-0.3% from 2021 on. Coefficients are
   unstable across rolling fits (vaccine RR 1.23 -> 0.94, IRS 0.83 -> 0.98) and the ITN
   gradient runs the wrong way. Most intervention variation is between districts and is already
   absorbed by the district effect and trend. **Decision: the main model omits interventions;
   SPEC int is reported as a sensitivity analysis.** The coefficients are nuisance terms, NOT
   impact estimates.
   **Zone adjustment helps across years:** CRPS 390.7 -> 362.9 (-7%), coverage 0.915 -> 0.932,
   flags 5.4% -> 4.1%. 2021 remains the weak year (coverage 0.87, flags 9.3%): the urban
   reporting step changes that Tier 3 is meant to classify.
8. DONE (2026-10-27): Tier 3 (`scripts/lib_tier3.R`, `08_tier3.R`) and synthetic validation
   (`09_synthetic.R`; 12,000 injected events, 2018-2025, main model, zone-adjusted flags).
   - Tier 3 on the real flags (965 in 2018-25): 41% transmission, 51% reporting, 8% indeterminate.
     The 2021 manual check is reproduced (Tema, Krowor transmission; Ayawaso Central, Achiase,
     Birim South reporting).
   - Sensitivity (any flag during the event): +25% 12% (1 month) / 20% (3 months); +50% 26% / 37%;
     doubling 62% / 73%. Background flag rate in the same months is 2-7%. Delay is 0 months when
     detected. False alerts are 4.0% of non-injected district-months.
   - Tier 3 on detected synthetic events: outbreaks labelled transmission 59% (+25%), 76% (+50%),
     91% (doubling); artefacts labelled reporting 56-70%. Calibration: best balanced accuracy 0.79
     (PM_T 1.3, TPR_T 0.01) vs 0.79 for the defaults (1.2, 0.02). **Defaults kept.**
   - **Main weakness: moderate rises.** Month-to-month noise is large (NB size ~7.8, CV ~0.36 per
     district-month). This frames the satellite test: **the value of the satellite layers =
     the sensitivity gain at a fixed 4% false-alert rate.**
9. DONE (2026-10-28): **MAIN MODEL = monthly-updated AR1 ("arm").** `07_model.R TARGET ar MONTH`:
   the district linear trend is replaced by a district x year AR1, and each month M is predicted
   from a fit on all months up to M-1 (96 fits, `out/monthly/`). Reason: the linear trend carried
   the 2019-21 urban reporting jumps forward for ever (base model, 2025: Ayawaso Central 18,341
   predicted vs 3,026 observed; Kumasi 69,545 vs 38,517); a yearly AR1 fit gave intervals so wide
   that only 0.2% of months were flagged. `scripts/lib_preds.R` loads either model; 08/09/10 take
   MODEL (arm default; base outputs kept with suffix `_base`, figures `_v2` are arm).
   - Two fits (Jul 2021, Jul 2023) failed to converge and INLA's automatic rerun returned junk
     (coverage 1.00, CRPS 18,000-23,500). Refitted with `INLA_SAFE=1` (Gaussian approximation,
     empirical-Bayes hyperparameters); failed outputs kept in `out/monthly/failed/`. Any future
     monthly run must check every log for "Error" and for coverage = 1.000.
   - **Skill, 2018-25 (zone-adjusted), arm vs base:** CRPS 237 vs 363 (-35%); coverage 0.966 vs
     0.932; flags 2.0% vs 4.1%; obs/pred 0.99-1.09 every year (base 0.91-1.19). 2021 is no longer
     a weak year (CRPS 253, coverage 0.965). Intervals are slightly conservative (nominal 0.95).
     Ayawaso Central and Kumasi now track: 2025 predicted 3,641 vs 3,026 and 38,131 vs 38,517.
   - **Synthetic, arm (false alerts 1.6-2.0%, half the base rate):** doubling 78% (1 month) / 94%
     (3 months); +50% 30% / 51%; +25% 9% / 18%. Better than base at every size except +25% in a
     single month (9% vs 12%), at half the false-alert rate. Months 2-3 are somewhat optimistic
     (no refit after injection; see 09_synthetic.R header).
   - Tier 3, real flags (472): 33% transmission, 59% reporting, 8% indeterminate. On synthetic
     events: outbreaks labelled transmission 49-50% (+25%), 69-75% (+50%), 89-90% (doubling);
     artefacts labelled reporting 63-74%. Balanced accuracy 0.80 (best PM_T 1.15, TPR_T 0.01) vs
     0.79 for defaults: **defaults kept.**
   - Satellite test is now: sensitivity gain **at a fixed ~2% false-alert rate**; comparators must be
     compared at matched false-alert rates (or on ROC-type curves), not at their own defaults.
10. DONE (2026-10-28): **comparators on the same synthetic outbreaks** (09 now saves every injected
   district-month to `out/synthetic_injections_arm.csv`; results unchanged). `11_farrington.R`
   (Farrington flexible, Noufaily nbPlugin, b = 3 years (2 for 2018), w = 1, per district, alpha
   varied), `12_consensus.py` (arXiv:2607.21559 consensus detector, made PROSPECTIVE and district-level;
   adaptations in the script header; q = per-detector percentile and S = votes varied),
   `13_compare.py` -> `out/comparison_outbreaks.csv`, `out/figures/fig7_comparison_v2.png`.
   - **Neither comparator is calibrated at its stated level.** Farrington alpha 0.05 flags 19% of
     real district-months, and even alpha 0.0001 flags 3.0% (it cannot reach our 2%). Consensus as
     published (q 0.10, S >= 3) flags 14%; q 0.02, S >= 3 gives 2.0%.
   - Outbreaks detected (1 month / 3 months):

     | Method (setting) | False alerts | +25% | +50% | doubling |
     |---|---|---|---|---|
     | This model (95%, zone-adjusted) | 1.8% | 9 / 18 | 30 / 51 | 78 / 94 |
     | Consensus (q 0.02, S >= 3) | 2.1% | 7 / 12 | 17 / 26 | 45 / 53 |
     | Farrington (alpha 0.0001) | 3.0% | 13 / 21 | 27 / 45 | 56 / 74 |
     | Consensus, published (q 0.10, S >= 3) | 14.5% | 30 / 38 | 45 / 58 | 76 / 83 |
     | Farrington, default (alpha 0.05) | 19.2% | 47 / 64 | 69 / 85 | 88 / 95 |

   - **This model dominates for +50% and doubling:** more outbreaks found at a lower false-alert
     rate than either comparator at any setting near it. For +25% it is level with the comparators'
     curves; no method detects small rises in one month. The published consensus setting matches
     our doubling sensitivity only at ~8x the false alerts (14.5% vs 1.8%).
   - Caveats: comparators were not given the zone adjustment; our model's months 2-3 are slightly
     optimistic (no refit after injection); consensus was made prospective (as published it learns
     from the months it judges, which a real-time system cannot do).
11. DONE (2026-10-28): **CUSUM tested and NOT adopted** (`scripts/14_cusum.R`, `out/cusum_arm.csv`).
   z = log(obs / adjusted median), scaled by the upper (or lower) half-width of the 95% interval, so
   z > 1.96 is exactly the existing flag; upper CUSUM C_t = max(0, C_{t-1} + z_t - K), alarm at C > H,
   then reset; alert = single flag OR CUSUM. K in {0.5, 1}, H in {2..6}, same injections as 09.
   **Fair test: against simply lowering the single-month threshold (z > C) to the same false-alert rate.**
   - K = 0.5, H = 3 (false alerts ~2.8%): +25% 11 / 23, +50% 31 / 62, doubling 78 / 96 (1 / 3 months).
     Single flag at C = 1.75 (~2.8%): 13 / 25, 40 / 62, 85 / 96. Lowering the threshold is as good or
     better in every cell.
   - K = 0.5, H = 2 (~3.6%) beats the single flag at C = 1.65 (~3.3%) only for 3-month events
     (+25% 34 vs 30, +50% 75 vs 68) and loses for 1-month events (+50% 32 vs 46). That gain sits in
     months 2-3, the part the no-refit design inflates most, so it is not trusted.
   - **Conclusion: one rule, a single-month threshold.** The real choice is the operating point, which
     belongs to the programme (how many alerts per month it can investigate):

     | Threshold | False alerts | +25% (1/3 mo) | +50% (1/3 mo) | doubling (1/3 mo) |
     |---|---|---|---|---|
     | z > 1.96 (95% limit, default) | 1.8% | 9 / 18 | 30 / 51 | 78 / 94 |
     | z > 1.75 | 2.8% | 13 / 25 | 40 / 62 | 85 / 96 |
     | z > 1.55 | 4.0% | 19 / 33 | 51 / 75 | 90 / 97 |

     2.0% of 247 districts = about 5 alerts a month nationally; 4% = about 10.
12. IN PROGRESS (2026-10-28): Earth Engine connected (project durable-circle-448314-t3). Dynamic World
   changed to ANNUAL cloud-masked label shares (see 03_gee_extract.py dynworld(): monthly
   probability means understated forest, e.g. Amansie West 7% trees; monthly composites were
   distorted by Harmattan haze and rainy-season cloud). DW drifts between years (Bole trees 39% ->
   74%, 2016 -> 2024), so the galamsey test must stay a within-forest-belt comparison.
   Then: satellite layers once extracted (each layer = 96 monthly refits, ~25 min at 3 in parallel;
   INLA_SAFE fallback for failed months). Their value = the gain on this table at a fixed false-alert
   rate. Then the galamsey analysis (s6b).
   - 2026-10-29: extraction of the nine main layers DONE (two hung requests overnight; requests now
     time out after 5 min and `scripts/gee_run.sh` restarts on failure). QA: ERA5 empty for Krowor and
     Ledzokuku (filled from neighbours); GSW ends 2021 (not used in the model; water from Dynamic
     World); IMERG ends Sep 2025 (sensitivity only); SMAP starts Apr 2015; DW 2015 weak (43
     districts > 20% unobserved). Panel: `scripts/15_satellite_panel.R` ->
     `data/derived/satellite_district_month.csv`.
   - Model SPEC sat in 07_model.R (arm + DLNM lags 0-3 for rain, LST, soil moisture, NDVI, ERA5;
     linear DW shares from the previous year + night lights). Runs: sat-all and one group at a time
     (rain, lst, sm, ndvi, era5, env), 96 monthly refits each (`scripts/run_sat_monthly.sh`); failed
     fits found by `16_check_fits.R`; value = outbreak sensitivity at a FIXED 2% false-alert rate
     (`17_satellite_value.R`, interpolated over the threshold grid of 14_cusum.R, now 1.45-2.4).
     Sentinel-1/2 layers (galamsey only) extracting in the background.
   - 2026-10-29 RESULT (`out/satellite_value.csv`, fig12). 672 monthly refits; 7 failed silently
     (coverage 1.000, CRPS ~10x) and were refitted with INLA_SAFE (failed outputs in
     out/monthly/failed/). Same 12,000 injections for every model (files identical). Outbreak
     sensitivity at a FIXED 2% false-alert rate (1 / 3-month events):

     | Model | +25% | +50% | doubling | CRPS |
     |---|---|---|---|---|
     | main (arm) | 9 / 19 | 30 / 54 | 79 / 95 | 237 |
     | + all layers | 13 / 25 | 43 / 70 | 88 / 97 | 215 |
     | + ERA5 temp/humidity | 12 / 25 | 41 / 67 | 85 / 97 | 220 |
     | + NDVI | 12 / 24 | 39 / 65 | 85 / 97 | 224 |
     | + LST | 10 / 22 | 36 / 63 | 83 / 97 | 223 |
     | + rainfall | 11 / 21 | 34 / 59 | 81 / 96 | 231 |
     | + land cover, night lights | 10 / 20 | 31 / 55 | 79 / 95 | 238 |
     | + soil moisture | 10 / 20 | 31 / 53 | 78 / 95 | 234 |

     Satellite + climate layers help detection, gain is largest for +50% outbreaks (+13 / +16
     points), CRPS lower in every year 2018-25. Temperature/humidity and NDVI carry most of it;
     rainfall alone adds little; soil moisture and the annual land-cover/night-light layers add
     nothing (slow-changing, absorbed by the district effects). Note ERA5 is reanalysis, not
     satellite. Still to do: uncertainty on the gains (bootstrap over events/years), Sentinel layers.
13. DONE (2026-10-30): **FINAL SYSTEM = sat-all** (monthly AR1 + all satellite/climate layers); arm is
   the "no satellite" reference. Re-run on sat-all: 08 Tier 3 (415 flags 2018-25: 42% transmission,
   51% reporting, 7% indeterminate; synthetic balanced accuracy 0.80 at the default thresholds, kept),
   13 comparators (fig7_v3 shows both model versions), figures 1-6 (_v3). 11/12 need no re-run
   (comparators do not depend on our model; injections identical).
   - Uncertainty: `scripts/20_bootstrap.R`, paired district bootstrap (247 districts resampled, same
     draw for both models), B = 2000, sensitivity at a fixed 2% false-alert rate. Gain of sat-all over
     arm, percentage points (95% interval): +25% 1 mo +3.9 (1.7, 5.8), 3 mo +6.3 (3.3, 9.8); +50% 1 mo
     +12.4 (8.1, 15.6), 3 mo +16.0 (11.7, 20.0); doubling 1 mo +8.8 (5.2, 11.8), 3 mo +2.4 (0.9, 4.1).
     Single layers, +50% 1 mo: ERA5 +10.4 (6.6, 13.5), NDVI +8.3 (4.8, 10.9), LST +5.3 (1.6, 8.9),
     rain +4.1 (1.3, 6.3), land cover/night lights +0.3 (-1.8, 2.3), soil moisture -0.1 (-2.2, 2.3).
   Next: galamsey (s6b), then writing.
14. DONE (2026-10-30): **real-event check** (`scripts/21_real_events.R`, events in
   `data/derived/real_events.csv`, sources in `docs/real_events_sources.md`). 14 documented events
   with named districts and months (12 floods incl. Bagre spillages 2018-25 and Akosombo/Kpong 2023,
   2 press reports of malaria rises), 57 event-districts; window = start month + 2.
   - Final model (sat-all): 9 of 57 flagged vs 3.9 expected from the same districts and calendar
     months in other years (Poisson P = 0.017). Median observed/expected 1.10 in the windows.
   - Without satellite (arm): 9 of 57 vs 7.4 expected (P = 0.33): arm flags these northern
     rainy-season months often anyway; the satellite model is more specific.
   - Most floods produce no detectable rise (median +10%, below the ~+25% the system can see).
     Clearest: Anloga after the Akosombo spillage (x1.79, flagged Oct-Dec 2023, Tier 3 "reporting":
     displacement and outreach raise attendance too, so Tier 3 is not built for disasters); South
     Tongu (x1.40, 2 transmission flags; corrected 2026-10-30, earlier value was wrong); Talensi Bagre 2025 (x1.58); North Tongu, the worst hit,
     ran BELOW expected (x0.89), consistent with facilities disrupted.
   - Framing: a plausibility check, not a validation. Floods need not raise malaria, documented
     events are few, and press reports are not case definitions.
15. DONE (2026-10-30): **galamsey** (`scripts/22_galamsey.R`, fig15, out/galamsey_*.csv). 116 forest-belt
   districts. Exposure face validity is strong: the largest 2016-24 bare-ground increases are Amansie
   West/South/Central, Wassa Amenfi East/Central/West, Atiwa East/West, Upper Denkyira West, Adansi
   North, Kwaebibirem, Bekwai. But the change is zero-inflated: the PRE-SPECIFIED top quartile (29)
   reaches districts with ~0 change; stricter >= 0.5 points (14 districts) added as sensitivity,
   decided from the exposure distribution before reading outcomes.
   - Pre-specified tests are NULL / uninformative: T1 residual excess per point of bare+water 1.004
     (0.998-1.009), extra slope in mining districts 1.001 (0.989-1.013); T2 (adapted: 2022-25 vs
     2018-21, flags exist only from 2018) flag rate ratio 1.17 (0.30-4.65). Expected: the AR1 absorbs
     slow rises, and flags are rare.
   - NOT pre-specified, on incidence with district + year effects, district-clustered SE: +2.8% per
     point of previous-year bare+water (1.1-4.6%, P = 0.001); +8.7% per point of Sentinel-1 radar
     water (4.3-13.2%, P < 0.001); both unchanged with a rainfall control (+2.8%, +8.2%). Differential
     trend in mining districts +1.8%/yr (-0.8 to 4.5), stricter definition +3.3%/yr (-0.2 to 6.8).
     Descriptive: mining/other incidence ratio 1.32 (2015) -> 1.64 (2025).
   - Reading: the detection system does not see galamsey (a slow change, absorbed as the new normal,
     which is what a detection system should do). Exploratory incidence models suggest more open
     water and bare ground go with more malaria. Report as exploratory; confounding by migration,
     health-service changes and DW drift remains. Next: writing.
16. DONE (2026-10-31): **clustered upsurges** (`scripts/23_clustered.R`, out/clustered_sat-all.csv). Upsurges
   injected into 1, 3, 5, 10 or 20 neighbouring districts at once (4 clusters per set, 5 sets per
   year, 2018-25), per-district sensitivity at a fixed 2% false-alert rate. Zone-adjusted (the
   system) vs raw vs either (max of the two scores):

   | +50%, 1 / 3 months | 1 | 3 | 5 | 10 | 20 districts |
   |---|---|---|---|---|---|
   | zone-adjusted | 43 / 66 | 39 / 74 | 40 / 65 | 35 / 58 | 27 / 46 |
   | raw | 35 / 65 | 38 / 71 | 37 / 64 | 40 / 67 | 37 / 67 |
   | either | 40 / 66 | 41 / 73 | 37 / 65 | 39 / 67 | 35 / 65 |

   The zone adjustment helps for upsurges in up to ~5 districts and HURTS for widespread ones (a
   20-district rise lifts the leave-one-out zone ratio and cancels itself; doubling 1 mo: 66% vs 83%
   raw). "Either" is robust across sizes at a cost of 2-3 points for single districts. Decision
   (proposed): keep the zone-adjusted district alert as the main rule (headline numbers unchanged);
   add a zone-wide signal (R_zone above its own limit, or the either-rule) as a second output for
   widespread rises, which are also where reporting changes are common, so Tier 3 applies. Report
   the size dependence as a result, not hide it.
17. DONE (2026-10-30): **prototype dashboard** for the supplement (`scripts/24_dashboard.py` +
   `scripts/dashboard_template.html` -> `out/dashboard/ghana_malaria_upsurge_dashboard_v2.html`, 1.1 MB,
   one self-contained file, no external libraries, works offline, light/dark). Month slider and play;
   district map coloured by alert + Tier 3 class or by observed/expected; per-district observed vs
   expected with 95% band and alert markers, plus rainfall, NDVI and temperature; monthly alert table;
   zone-wide observed/expected panel (no threshold set). Labelled as a retrospective research
   prototype, not operational. Contains district-level DHIMS2 counts: check permission before sharing.
18. DONE (2026-10-30): **real-time robustness, lags 1-3 only** (`SATLAG0=0 SAT=all`, model `sat-all-l13`;
   96 refits, 1 hung (2025-03) and was refitted with INLA_SAFE; all pass 16_check_fits.R). Same-month
   satellite values dropped, so month M uses only data available before M.
   - Sensitivity at a fixed 2% false-alert rate (1 / 3 months): +25% 13 / 25, +50% 43 / 70, doubling
     86 / 97; CRPS 215.2 (sat-all 214.9, arm 237.2); CRPS by year within 1 of sat-all every year.
   - Gain over arm (paired district bootstrap, B = 2000, `out/bootstrap_arm_vs_sat-all-l13.csv`), points
     (95% interval): +25% +3.8 (1.6, 5.5) / +6.9 (3.6, 9.6); +50% +12.8 (8.0, 16.2) / +15.7 (11.2, 19.5);
     doubling +7.3 (3.9, 10.1) / +2.4 (0.9, 4.1).
   - sat-all vs sat-all-l13 (`out/bootstrap_sat-all-l13_vs_sat-all.csv`): no difference in any cell except
     doubling 1 mo, +1.5 (0.1, 3.1) for lag 0.
   - Reading: the satellite gain does NOT depend on same-month data; it comes from conditions in the
     previous 1-3 months, which is biologically sensible (mosquito and parasite development). sat-all
     stays the final system (lag-0 layers arrive before the DHIMS2 monthly report closes); sat-all-l13
     is reported as the robustness check. `out/satellite_value.csv` now includes it (previous version kept
     as `_before_l13`).
19. DONE (2026-10-30): paper figures fig16-19 (`scripts/25_paper_figures.py`: gain with bootstrap
   intervals, skill by year, cluster size, documented events; use fig19 _v2). Manuscript drafts:
   `docs/manuscript/02_methods.md`, `03_results.md` (draft 1). Target journal Malaria Journal.
20. DECIDED (2026-10-31): the system is **early DETECTION**, not early warning (WHO sense: warning = forecast
   before the rise, detection = flag a rise under way from case data). Title, Methods and dashboard (v4)
   changed. A one-month-ahead forecast from the lags-1-3 model is a Discussion point (future work), not a claim.
21. DONE (2026-10-31): full first draft in `docs/manuscript/`: 00_title_abstract (340 words), 01_introduction,
   02_methods, 03_results, 04_discussion (+ Conclusions), references.md (keyed; 16 methods/data refs marked
   [CHECK], added from memory). Drafts use bullets for readability; convert to journal prose at final assembly.
   Open: data access + ethics statements, repository URL, author list, Table 1 (layers), supplement.
22. DONE (2026-10-31): **assembled manuscript v1** in journal prose: `docs/manuscript/manuscript_source.md`
   (THE file to edit from now on; citations as [Key]) -> `scripts/26_assemble_manuscript.py` -> numbered
   `manuscript_vN.md` + `.docx` (never overwrites). Includes Table 1 (layers), Tables 2-3, figure legends
   (Figs 1-10 mapped to out/figures files), abbreviations, declarations. ~5,800 words main text, 55 refs
   (18 marked [CHECK] in references.md). Supplement: `docs/manuscript/supplement.md` (Notes S1-S7,
   Figs S1-S8, dashboard as Additional file 2). Bulleted drafts 00-04 are superseded (kept for reference).
23. DONE (2026-10-31): **exposure-response** (`scripts/27_exposure_response.R`, `28_exposure_figures.py`; fig20, fig21;
   out/exposure_response_*.csv; samples cached in out/exposure_response_samples.rds). sat-all fitted once on all
   data (1.1 min; coefficients match the Dec 2025 monthly fit). Conditional on season/district/year/AR1, so
   = response to departures from the usual pattern. P10 / P90 vs median, cumulative lags 0-3: air temp inverted U
   (peak ~27.5 C; 24.7 C 0.81, 29.4 C 0.92); LST day hot 0.81; LST night warm 1.03; NDVI 0.87 / 1.10; RH high 1.04;
   dry soil 0.91; rain net ~0 but lag 0 0.96 -> lag 3 1.03; built-up 0.84 per SD; bare ground 0.98 per SD (AR1
   absorbs slow change). In manuscript (Methods, Results, Discussion; Note S8, Figs S9-S10) -> manuscript_v2.
24. DONE (2026-11-01): **interventions and alerts** (`scripts/29_interventions_alerts.R`). Interventions stay OUT of
   the model (no prediction gain; a failure should show as an upsurge) - argued in the Discussion.
   - IRS insecticide switch (Coleman 2026 Table 1 transcribed: `data/derived/irs_insecticide_cole2026.csv`; 22
     districts, first neonicotinoid year 2018/2019/2020). Switch year: 64% of districts alerted vs 22% other North;
     1.50 vs 0.34 alerts/district-year; obs/exp 1.19. DiD (district + year FE): switch year + next, RR 3.76
     (2.17-6.51); transmission 4.78 (2.19-10.46). Back to baseline from year 2 (AR1 adapts). Districts Coleman
     found unchanged/lower (KNW, Mamprugu-Moagduri, Kumbungu, Wa) had 0 alerts. Confounders: SMC to all IRS
     districts 2019; IRS districts excluded from net campaigns. The best real-world check we have.
   - Net campaign age: null (collinear with calendar year). SMC months: null interaction 1.43 (0.84-2.42).
   - In manuscript v3 (Methods, Results "Interventions", Table 4, Discussion paragraph, abstract line; Note S9).

25. Seasonality vs climate (2026-11-13; scripts/33_seasonality_climate.R, 34_seasonality_figure.py, fig23). Five all-data fits differing only in climate terms. Peak-to-trough of the zone seasonal term without climate: North 3.44, Forest 1.63, Coast 1.53; with all climate + env: 1.39, 1.32, 1.36 (74%, 43%, 27% of log amplitude taken over). Rain+soil+NDVI alone take 64/62/73%; adding temperature lets the seasonal term regrow in the south (temperature cycle runs opposite, collinearity). Climatology xcorr: cases follow rain by 2 months in North (r 0.94), 1 month in south (0.82-0.86). Timing: North case-season centre shifts 0.43 months per month of rain-season shift (0.22-0.65) across district-years, but 0.13 (-0.22-0.48) with year effects, i.e. the co-movement is zone-wide year-to-year; Coast NDVI timing 0.15 (0.04-0.26) within year. Not in the manuscript yet.
