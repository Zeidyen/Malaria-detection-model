# Raw inputs

- `dhims_national_2015_2025.csv`: Zeid's own DHIMS2 district-month malaria extract (received
  9 Oct 2026; 248 districts x 132 months, all ages, suspected/tested/confirmed). Copied
  unchanged from ~/Downloads/smc-regimen-delivery/geo/data/raw/dhims/, where it was flattened
  from `Malaria_population_district_data.xlsx` (sheet "National") by that folder's
  00_dhims_prepare.R. Cleaned upstream by the data source (method unknown); see
  scripts/01b_imputation_check.R.
- `gha_ADM2.geojson`: geoBoundaries Ghana ADM2, 260 districts.
