#!/usr/bin/env python3
"""Build district-by-year malaria intervention tables for Ghana, 2015-2025.

Output: data/derived/interventions_district_year.csv (247 units x 11 years).
Every coded value carries a source ID, documented in data/derived/interventions_sources.md.
NA means unknown (no source, region-level only, or sources conflict); it is never 0.

Columns
  smc, smc_cycles, smc_source          main SMC coding. Outside the five northern regions
                                       SMC = 0 by the author's programme knowledge (AUTH),
                                       which public sources contradict for Oti and Bono East.
  smc_alt, smc_alt_cycles, smc_alt_source   SMC coded from public sources only (differs from
                                       the main coding only in Oti and Bono East).
  irs, irs_programme, irs_month, irs_source
  itn_campaign, itn_month, itn_source  district-level mass-campaign status (strict).
  itn_campaign_region, itn_month_region, itn_region_source   region-level campaign status
                                       (region had a campaign round that year); not district-level.
  vaccine, vaccine_product, vaccine_source

Vaccine pilot membership (2019-2022) is read from a published map (Adjei et al. 2023, BMC
Public Health, Fig 1) overlaid on units_simplified.geojson; the overlay result is in
scripts/data/malaria_vaccine_units.csv (copied from the research scratch work).
"""
import csv
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNITS = os.path.join(ROOT, "data", "derived", "units_list.csv")
VAX = os.path.join(ROOT, "scripts", "data", "malaria_vaccine_units.csv")
OUT = os.path.join(ROOT, "data", "derived", "interventions_district_year.csv")
YEARS = range(2015, 2026)
NA = "NA"

units = list(csv.DictReader(open(UNITS)))
assert len(units) == 247, len(units)
REG = {u["unit"]: u["Region"] for u in units}
by_region = {}
for u in units:
    by_region.setdefault(u["Region"], []).append(u["unit"])

NORTH5 = {"Upper West", "Upper East", "Northern", "North East", "Savannah"}
NR_OLD = {"Northern", "North East", "Savannah"}  # pre-2019 Northern Region
UW = by_region["Upper West"]
UE = by_region["Upper East"]
for k in UW + UE:
    assert k in REG

# ---------------------------------------------------------------- IRS facts
# PMI district lists (unit keys). Bunkpurugu-Yunyoo (split 2018) -> both successor units.
PMI5 = ["bunkpurugunakpanduri", "yunyoonasuan", "eastmamprusi", "kumbungu",
        "mamprugumoagduri", "westmamprusi"]
PMI7 = PMI5 + ["gushegu", "karaga"]
PMI9 = PMI7 + ["tatalesanguli"]
PMI10 = PMI9 + ["chereponi"]
PMI = {  # year: (units, month, source)
    2015: (PMI5, "Apr-May", "IAIA2019;GOGUE2020;MOP18"),
    2016: (PMI5, NA, "MOP18;GOGUE2020"),
    2017: (PMI7, "Apr-May", "MOP18;GOGUE2020;CITI2017"),
    2018: (PMI7, "Apr-Jun", "VL18"),
    2019: (PMI7, "Apr-May", "VL19"),          # 8 districts after the split = 8 units
    2020: (PMI9, "Mar-Apr", "VL20"),
    2021: (PMI9, "Mar-May", "VL21"),
    2022: (PMI9, "Mar-Apr", "VL22;MOP24"),
    2023: (PMI9, NA, "MOP24;VLF;PROF24"),
    2024: (PMI10, NA, "MOP24;MOP23;GNA2024IRS"),
    2025: (PMI10, "Jun-Jul", "EV3"),
}
for y, (lst, _, _) in PMI.items():
    for k in lst:
        assert k in REG, k

UE3 = ["builsanorth", "builsasouth", "kasenanankanawest"]
OBU = ["obuasi", "obuasieast"]


def irs_cell(k, y):
    """Return (irs, programme, month, source)."""
    r = REG[k]
    lst, mon, src = PMI[y]
    if k in lst:
        return 1, "PMI", mon, src
    if r in NR_OLD:
        # PMI lists are complete for each year; Global Fund/AGAMal never sprayed in these regions
        return 0, "none", NA, src + ";MOP20;PROF24"
    if r == "Upper West":
        if y <= 2017:
            return 1, "AGAMal/GF", NA, "GOGUE2020;COLE2026"
        if y == 2018:
            return 1, "AGAMal/GF", NA, "COLE2026;MOP18"
        if y == 2019:
            return 1, "AGAMal/GF", "Mar-May", "BG2019;MOP20;COLE2026"
        if y <= 2022:
            return 1, "AGAMal/GF", NA, "COLE2026" + (";JOY2022" if y == 2022 else "")
        if y <= 2024:
            return 1, "AGAMal/GF", NA, "PROF24;GNA2024AGA"
        return NA, NA, NA, "NF"
    if r == "Upper East":
        if k in UE3:
            if y in (2015, 2016):
                return 0, "none", NA, "GOGUE2020;IVCC2019"
            if y == 2017:
                return 1, "AGAMal/GF", "Aug-Sep", "GOGUE2020"
            if y == 2018:
                return 1, "AGAMal/GF", NA, "COLE2026;MOP18"
            if y == 2019:
                return 1, "AGAMal/GF", "Mar-May", "BG2019;MOP20;COLE2026"
            if y == 2020:
                return NA, NA, NA, "CONFLICT:COLE2026_vs_ADJEI2024UE"
            if y == 2021:
                if k == "builsanorth":
                    return 1, "AGAMal/GF", NA, "COLE2026;ADJEI2024UE"
                return NA, NA, NA, "CONFLICT:COLE2026_vs_ADJEI2024UE"
            if y == 2022:
                return 1, "AGAMal/GF", NA, "COLE2026;ADJEI2024UE;JOY2022"
            if y <= 2024:
                return 1, "AGAMal/GF", NA, "PROF24;GNA2024AGA;COLE2026"
            return NA, NA, NA, "NF"
        # other 12 Upper East units
        if y <= 2017:
            return 0, "none", NA, "GOGUE2020"
        if y <= 2024:
            return 0, "none", NA, "COLE2026;PROF24" + (";ADJEI2024UE" if k == "kasenanankanaeast" and y in (2020, 2021, 2022) else "")
        return NA, NA, NA, "NF"
    if k in OBU:
        # Obuasi East was carved out of Obuasi in 2018; earlier statements on "Obuasi" cover both units
        if y in (2016, 2017):
            return 1, "AGAMal", NA, "MOP18"
        if y == 2019:
            return 1, "AGAMal/GF", "Mar-May", "BG2019;MOP20"
        if y == 2022:
            return 1, "AGAMal/GF", NA, "JOY2022"
        if y in (2023, 2024):
            return 1, "AGAMal/GF", NA, "PROF24;GNA2024AGA"
        return NA, NA, NA, "NF"
    # rest of the country: IRS only in the north and Obuasi
    return 0, "none", NA, "COLE2026;MOP18;PROF24"


# ---------------------------------------------------------------- SMC facts
PMI_IRS_BY_YEAR = {y: set(PMI[y][0]) for y in YEARS}


def smc_north(k, y):
    """Public-source SMC coding for the five northern regions: (smc, cycles, source)."""
    r = REG[k]
    if r == "Upper West":
        if y == 2015:
            return 1, 4, "GOGUE2020;NONVIGNON2016"
        if y == 2016:
            return 1, 2, "GOGUE2020"
        if y == 2017:
            return 1, 4, "GOGUE2020"
        if y == 2018:
            return NA, NA, "REGION_ONLY:MOP19"
        cyc = {2021: 4, 2022: 4, 2023: 4}.get(y, NA)
        src = {2021: "COLE2026;MOP23", 2022: "COLE2026;MOP24", 2023: "COLE2026;SMCALL"}.get(y, "COLE2026")
        return 1, cyc, src
    if r == "Upper East":
        if y == 2015:
            return 0, 0, "GOGUE2020;MOP16"
        if y == 2016:
            return 1, 2, "GOGUE2020"   # Citi FM/Graphic 2016 announced 4 phases Aug-Nov: conflict on cycles
        if y == 2017:
            return 1, 4, "GOGUE2020"
        if y == 2018:
            return NA, NA, "REGION_ONLY:MOP19"
        if y == 2019:
            if k in UE3:
                return 1, NA, "COLE2026"
            return NA, NA, "REGION_ONLY:MOP19"
        if y == 2020:
            return 1, 4, "ADJEI2024UE;GNA2020UE"
        if y == 2021:
            return 1, 4, "ADJEI2024UE;MOP23"
        if y == 2022:
            return 1, 4, "ADJEI2024UE;GNA2022UE;MOP24"
        if y == 2023:
            return 1, 4, "SMCALL"
        if y == 2024:
            if k == "bolgatanga":
                return 1, 5, "GNA2024BOLGA;GHTIMES2025"
            if k in ("kasenanankanaeast", "kasenanankanawest", "builsanorth", "builsasouth"):
                return 1, NA, "AYAMBA2025;GHTIMES2025;CONFLICT_CYCLES_4v5"
            return NA, NA, "REGION_ONLY:GHTIMES2025;SMCALL"
        if y == 2025:
            return 1, NA, "GNA2025UE"
    # Northern, North East, Savannah
    if y <= 2018:
        if k == "tamale" and y in (2017, 2018):
            return NA, NA, "CONFLICT:SAYIBU2025_vs_MOP18"
        return 0, 0, "MOP18;MOP19"
    if r == "Savannah" and y == 2019:
        return 1, 4, "ADJEI2022SAV;MOP20"
    if y in (2019, 2020, 2021):
        cyc_n = 3 if (y == 2021 and r == "Northern") else 4
        if k in PMI_IRS_BY_YEAR[y]:
            if y == 2019:
                return 1, 4, "COLE2026;MOP19;MOP20"
            if y == 2020:
                return 1, NA, "COLE2026;GHSC2021"
            return 1, cyc_n, "COLE2026;MOP23"
        if k == "tamale":
            return 1, (3 if y == 2021 else 4), "SAYIBU2025" + (";MOP23" if y == 2021 else "")
        return NA, NA, "REGION_ONLY:" + {2019: "MOP19;MOP20", 2020: "GHSC2021", 2021: "MOP23"}[y]
    if y == 2022:
        return 1, 4, "MOP24;MOP22"
    if y == 2023:
        return 1, 4, "MOP22;SMCALL"
    if y == 2024:
        return 1, 5, "MOP23;GHTIMES2025;SMCALL"
    if y == 2025:
        if r == "Savannah":
            return 1, 4, "MOP24;PADFM2025"
        return 1, NA, "MOP24"


def smc_cells(k, y):
    r = REG[k]
    if r in NORTH5:
        s = smc_north(k, y)
        return s, s
    main = (0, 0, "AUTH")
    if r == "Oti":
        if y <= 2020:
            alt = (0, 0, "MOP20;MOP22")
        elif y == 2021:
            alt = (NA, NA, "REGION_ONLY:MOP22;MOP23")
        elif y == 2022:
            alt = (1, 4, "MOP24;MOP22")
        elif y == 2023:
            alt = (1, 4, "MOP22;SMCALL" + (";GNAKADJ2023" if k == "kadjebi" else ""))
        elif y == 2024:
            alt = (1, (NA if k != "kadjebi" else NA), "MOP23;GHTIMES2025" + (";GNAKADJ2024" if k == "kadjebi" else ""))
        else:
            alt = (1, NA, "MOP24")
        return main, alt
    if r == "Bono East":
        if y <= 2020:
            alt = (0, 0, "MOP20;MOP22")
        elif k == "seneeast" and y == 2025:
            alt = (1, NA, "MNM2025;MOP24")
        else:
            alt = (NA, NA, "COUNT_ONLY:MOP22;MOP23;MOP24(5 of 11 districts, unnamed)")
        return main, alt
    return main, main


# ---------------------------------------------------------------- ITN facts
ALLREG = sorted(by_region)
# region-level campaign rounds: {year: {region: (1/0, month, source)}}
ITN_REG = {y: {} for y in YEARS}


def setreg(y, regions, val, mon, src):
    for r in regions:
        ITN_REG[y][r] = (val, mon, src)


# 2015 (2014-16 rolling PMD): Ashanti, Brong Ahafo, Central, Western in 2015
for r in ALLREG:
    setreg(2015, [r], 0, NA, "MOP18")
setreg(2015, ["Ashanti", "Central"], 1, NA, "MOP18")
setreg(2015, ["Ahafo", "Bono", "Bono East", "Western", "Western North"], 1, "Apr-May", "MOP18;MOP16")
# 2016: Greater Accra, Upper East, Upper West, Northern
for r in ALLREG:
    setreg(2016, [r], 0, NA, "MOP18")
setreg(2016, ["Northern", "North East", "Savannah"], 1, "Apr", "MOP18;AMF200;AFAG2022")
setreg(2016, ["Upper West"], 1, "Sep", "MOP18;AMF203;ERD2016")
setreg(2016, ["Greater Accra"], 1, "Jul", "MOP18;AMF204")
setreg(2016, ["Upper East"], 1, NA, "MOP18")
# 2017, 2019, 2020, 2023: no mass campaign round
for y in (2017, 2019, 2020, 2023):
    setreg(y, ALLREG, 0, NA, {2017: "MOP18;MOP20", 2019: "MOP20", 2020: "MOP20;MOP22", 2023: "MOP23"}[y])
# 2018: 9 of 10 old regions, Upper West excluded
setreg(2018, ALLREG, 1, NA, "AFAG2022;PMD2018")
setreg(2018, ["Upper West"], 0, NA, "AFAG2022;PMD2018")
setreg(2018, ["Volta", "Oti"], 1, "Mar-Apr", "AFAG2022;CITI2018VOLTA")
setreg(2018, ["Ashanti"], 1, "Nov", "AFAG2022;CITI2018ASH")
setreg(2018, ["Northern"], 1, "Jun", "AFAG2022;MOP20")
# 2021 round (15 regions, Upper West excluded); Ashanti delivered Feb-Mar 2022
setreg(2021, ALLREG, 1, NA, "MOP22;VLF")
setreg(2021, ["Upper West"], 0, NA, "MOP22")
setreg(2021, ["Ashanti"], 0, NA, "DEPSOCOM2022;GNA2022ASH")
setreg(2021, ["Upper East"], 1, "Apr", "MOP22;GNA2021UE")
setreg(2021, ["Volta"], 1, "Nov-Dec", "MOP22;GNA2021VOLTA")
setreg(2021, ["Eastern", "Greater Accra"], 1, "Oct-Dec", "MOP22;VL22")
setreg(2022, ALLREG, 0, NA, "VL22")
setreg(2022, ["Eastern", "Greater Accra"], 1, "Jan-Mar", "VL22")
setreg(2022, ["Ashanti"], 1, "Feb-Mar", "DEPSOCOM2022;GNA2022ASH")
# 2024 round: nationwide except some urban centres and all IRS districts
setreg(2024, ALLREG, 1, NA, "PROF24;MOP23;MOP24")
setreg(2024, ["Upper West"], 0, NA, "PROF24")          # every Upper West district is an IRS district
setreg(2024, ["Greater Accra"], NA, NA, "NF")          # Accra and Tema were done in 2025
setreg(2024, ["Volta"], 1, "Apr", "PROF24;GNA2024VOLTA")
setreg(2024, ["Central"], 1, "May", "PROF24;GNA2024CEN")
setreg(2024, ["Bono", "Ahafo"], 1, "May", "PROF24;GNA2024BONO")
setreg(2024, ["Ashanti"], 1, "Jul", "PROF24;GNA2024ASH")
setreg(2024, ["Oti"], 1, NA, "PROF24;GNA2024KADJ")
setreg(2025, ALLREG, NA, NA, "NF")
setreg(2025, ["Greater Accra"], 1, "Apr-May", "ADOM2025;GNA2025TEMA")


def irs_units(y):
    return {k for k in REG if irs_cell(k, y)[0] == 1}


def itn_cell(k, y):
    """District-level campaign status: (itn, month, source)."""
    r = REG[k]
    rv, rmon, rsrc = ITN_REG[y][r]
    if rv == 0:
        return 0, NA, rsrc
    if rv == NA:
        return NA, NA, rsrc
    # region had a campaign round this year
    if y == 2015:
        if k in OBU:
            return NA, NA, "MOP16(1 Ashanti IRS district excluded, unnamed)"
        return NA, NA, "REGION_ONLY:" + rsrc
    if y == 2016:
        if r in NR_OLD:
            return 1, "Apr", "AMF200"           # all 26 districts of the old Northern Region
        if r == "Upper West":
            return 1, "Sep", "AMF203;ERD2016"   # all 11 districts
        if k == "accra":
            return 0, NA, "AMFAGR2016"          # Accra Metropolitan excluded
        return NA, NA, "REGION_ONLY:" + rsrc
    if y in (2018, 2021, 2022, 2024):
        if k in irs_units(y) or (y == 2022 and k in OBU):
            return 0, NA, {2018: "AFAG2022;PMD2018", 2021: "MOP22;GNA2021UE", 2022: "DEPSOCOM2022",
                           2024: "PROF24;MOP23;MOP24"}[y]
        if y == 2018:
            if r in ("Volta", "Oti"):
                return 1, "Mar-Apr", "CITI2018VOLTA"    # all 25 districts of the 2018 Volta Region
            if k in ("zabzugu", "nanumbasouth"):
                return 1, "Jun", "MOP20;VLF"
        if y == 2021 and r == "Upper East":
            return 1, "Apr", "GNA2021UE"                # 12 of 15 districts; the 3 IRS districts excluded
        if y == 2022 and r == "Ashanti":
            late = {"asanteakimsouth", "adansisouth", "adansinorth", "ahafoanosoutheast",
                    "ahafoanosouthwest", "amansiesouth"}
            if k in late:
                return NA, NA, "GNA2022ASH(served later, date unknown)"
            return 1, "Feb-Mar", "GNA2022ASH;DEPSOCOM2022"
        if y == 2024:
            if r == "Volta":
                return 1, "Apr", "GNA2024VOLTA"         # all 18 districts
            if r == "Central":
                return 1, "May", "GNA2024CEN"           # "all districts of the region"
            if r == "Ashanti":
                return 1, "Jul", "GNA2024ASH;PROF24"    # 41 of 43 districts = all but the 2 IRS districts
            if k == "kadjebi":
                return 1, "Aug", "GNA2024KADJ"
        return NA, NA, "REGION_ONLY:" + rsrc
    if y == 2025 and r == "Greater Accra":
        if k == "accra":
            return 1, "May", "ADOM2025"
        return NA, NA, "REGION_ONLY:" + rsrc
    return NA, NA, "REGION_ONLY:" + rsrc


# ---------------------------------------------------------------- vaccine facts
vax = {v["unit"]: v for v in csv.DictReader(open(VAX))}
assert set(vax) == set(REG)


def vax_cell(k, y):
    ph = vax[k]["phase"]
    if ph == "MVIP_pilot_2019-05":
        src = "ADJEI2024UE;PMC9666942" if REG[k] == "Upper East" else "ADJEI2023PIE_MAP;ADJEI2024HEL"
        return 1, "RTS,S", src + (";JALANGO2025" if y >= 2023 else "")
    if ph == "expansion_2023-02":
        if y <= 2022:
            src = "ADJEI2024UE" if REG[k] == "Upper East" else "ADJEI2023PIE_MAP;ADJEI2024HEL"
            return 0, NA, src + ";JALANGO2025"
        return 1, "RTS,S", "JALANGO2025;ADJEI2024HEL;GAVI2024"
    if ph == "expansion_2024-09":
        if y <= 2023:
            return 0, NA, "ADJEI2024HEL;UNICEF2024"
        return 1, "R21 or RTS,S (conflict)", "UNICEF2024;GRAPHIC2024;GNA2025VAX"
    # never covered (North East, Ashanti, Eastern, Western, Greater Accra)
    if y <= 2024:
        return 0, NA, "ADJEI2024HEL;UNICEF2024"
    return NA, NA, "NF(no 2025 expansion found)"


# ---------------------------------------------------------------- assemble
cols = ["unit", "Region", "District", "year",
        "smc", "smc_cycles", "irs", "irs_programme", "irs_month",
        "itn_campaign", "itn_month", "vaccine", "vaccine_product",
        "smc_source", "irs_source", "itn_source", "vaccine_source",
        "smc_alt", "smc_alt_cycles", "smc_alt_source",
        "itn_campaign_region", "itn_month_region", "itn_region_source"]
rows = []
for u in sorted(units, key=lambda x: x["unit"]):
    k = u["unit"]
    for y in YEARS:
        (s, sc, ss), (sa, sac, sas) = smc_cells(k, y)
        if s == 0:
            sc = 0
        i, ip, im, isrc = irs_cell(k, y)
        if i == 0:
            ip = "none"
        t, tm, tsrc = itn_cell(k, y)
        rv, rmon, rsrc = ITN_REG[y][REG[k]]
        v, vp, vsrc = vax_cell(k, y)
        rows.append(dict(unit=k, Region=u["Region"], District=u["District"], year=y,
                         smc=s, smc_cycles=sc, irs=i, irs_programme=ip, irs_month=im,
                         itn_campaign=t, itn_month=tm, vaccine=v, vaccine_product=vp,
                         smc_source=ss, irs_source=isrc, itn_source=tsrc, vaccine_source=vsrc,
                         smc_alt=sa, smc_alt_cycles=sac, smc_alt_source=sas,
                         itn_campaign_region=rv, itn_month_region=rmon, itn_region_source=rsrc))

with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    w.writerows(rows)

assert len(rows) == 247 * 11
# coverage summary
for var in ["smc", "smc_cycles", "smc_alt", "irs", "irs_month", "itn_campaign", "itn_month",
            "itn_campaign_region", "vaccine"]:
    known = sum(1 for r in rows if r[var] != NA)
    ones = sum(1 for r in rows if str(r[var]) not in ("NA", "0"))
    print(f"{var:20s} known {known:5d} / {len(rows)}  NA {len(rows)-known:5d}  non-zero {ones:5d}")
print("wrote", OUT)
