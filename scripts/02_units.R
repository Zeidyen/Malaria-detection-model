# Analysis units: DHIMS2 districts (248) matched to geoBoundaries ADM2 polygons (260).
# DHIMS reports on an older district list. Three DHIMS districts cover several polygons
# (later splits), so those polygons are dissolved into one unit:
#   Kumasi      = Kumasi + Asokwa + Kwadaso + Oforikrom + Old Tafo + Suame
#   Accra Metro = Accra + Ablekuma Central/North/West + Ayawaso East/North/West + Okaikwei North
#   Tema        = Tema + Tema West
# Guan (Oti) has no polygon in this 260-district set: it is the 261st district, split from
# the northern part of Hohoe Municipal (Volta) on 8 Oct 2021 and moved to Oti
# (https://en.wikipedia.org/wiki/Guan_District; Graphic, GNA inauguration reports). DHIMS
# back-dates both to 2015, so Guan's cases and population are ADDED to Hohoe, whose
# polygon still covers both. The merged unit crosses the 2021 Volta/Oti boundary and is
# labelled Volta. Result: 247 units, every polygon used exactly once, no district dropped.
# Output: data/derived/units.gpkg, data/derived/cases_district_month.csv
suppressMessages({library(dplyr); library(sf)}); sf_use_s2(FALSE)
SRC <- "data/raw"
d <- read.csv(file.path(SRC, "dhims_national_2015_2025.csv"), check.names = FALSE)
a <- st_read(file.path(SRC, "gha_ADM2.geojson"), quiet = TRUE)
key <- function(v) sub("(municipal|metropolitan|metropolis|metro)$", "", gsub("[^a-z]", "", tolower(v)))
a$k <- key(a$shapeName)
d$k <- key(d$District)

# DHIMS spelling -> geoBoundaries spelling (checked one by one against the region lists)
alias <- c(asantemampong = "mampong", atwimanwabiagya = "atwimanwabiagyasouth",
  sekyereaframplains = "sekyereaframplainsnorth", berekum = "berekumeast",
  atebubuamanten = "atebubuamantin", pru = "prueast", assinfoso = "assinfosu", efutu = "effutu",
  komendaednaeguafoabirem = "komendaedinaeguafoabirem", twifoatimorkwa = "twifoattimorkwa",
  akwapimnorth = "akwapemnorth", akwapimsouth = "akwapemsouth", akyemansa = "akyemmansa",
  asenemansoakroso = "aseneakrosomanso", lowermanyakrobo = "lowermanya",
  uppermanyakrobo = "uppermanya", adentan = "adenta", afadjatosouth = "afadzatosouth",
  agortimeziope = "agotimeziope",
  # northern spellings, from smc-regimen-delivery 00_dhims_prepare.R
  gushiegu = "gushegu", sagnarigu = "sagnerigu", tatalesangule = "tatalesanguli",
  bolgatangaeast = "bolgaeast", kasenanankana = "kasenanankanaeast", lambussie = "lambussiekarni")
d$k <- ifelse(d$k %in% names(alias), alias[d$k], d$k)

# polygon -> DHIMS unit
merge_into <- c(asokwa = "kumasi", kwadaso = "kumasi", oforikrom = "kumasi", oldtafo = "kumasi",
  suame = "kumasi", ablekumacentral = "accra", ablekumanorth = "accra", ablekumawest = "accra",
  ayawasoeast = "accra", ayawasonorth = "accra", ayawasowest = "accra", okaikweinorth = "accra",
  temawest = "tema")
a$unit <- ifelse(a$k %in% names(merge_into), merge_into[a$k], a$k)
d$k[d$k == "guan"] <- "hohoe"
stopifnot(setequal(unique(d$k), unique(a$unit)), n_distinct(d$k) == 247)

u <- a |> group_by(unit) |> summarise(n_polygons = n(), .groups = "drop") |>
  left_join(distinct(filter(d, District != "Guan"), unit = k, Region, District), by = "unit")
u$District[u$unit == "hohoe"] <- "Hohoe + Guan"
stopifnot(nrow(u) == 247, !anyNA(u$District))
st_write(u, "data/derived/units.gpkg", delete_dsn = TRUE, quiet = TRUE)

ages <- c("u5", "5_14", "ov15")
out <- d |> transmute(unit = k, Region, District, year, m,
  pop_u5 = Pop_5, pop_5_14 = `Pop 5-14 years`, pop_tot = `Pop (total)`,
  across(c(paste0("allout_", ages), paste0("susp_", ages), paste0("test_", ages), paste0("conf_", ages))),
  conf_tot) |>
  group_by(unit, year, m) |>
  summarise(Region = first(Region[District != "Guan"]), District = paste(District, collapse = " + "),
            across(where(is.numeric), sum), .groups = "drop") |>
  relocate(Region, District, .after = unit) |> arrange(unit, year, m)
stopifnot(nrow(out) == 247 * 132)
write.csv(out, "data/derived/cases_district_month.csv", row.names = FALSE)
cat("units", nrow(u), "| merged units", sum(u$n_polygons > 1), "| district-months", nrow(out),
    "| Guan merged into Hohoe\n")
cat("conf_tot 2015-2025 total (millions):", round(sum(out$conf_tot) / 1e6, 2), "\n")

# Simplified outlines for Earth Engine (03_gee_extract.py); 0.005 deg ~ 500 m, well below
# the 1 km satellite pixels.
us <- st_simplify(u[, c("unit", "Region", "District")], dTolerance = 0.005, preserveTopology = TRUE)
st_write(us, "data/derived/units_simplified.geojson", delete_dsn = TRUE, quiet = TRUE)
cat("simplified outlines:", round(file.size("data/derived/units_simplified.geojson") / 1e6, 1), "MB\n")
