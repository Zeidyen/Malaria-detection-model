# Ghana malaria interventions by district and year, 2015-2025: sources, coding rules and gaps

Table: `data/derived/interventions_district_year.csv`, built by `scripts/04_interventions.py`. It has 247 units x 11 years = 2,717 rows, keyed by `unit` from `units_list.csv`.

**What NA means.** NA means unknown. A cell is NA when no source was found, when the source is region-level only, or when sources conflict. NA is never used to mean 0.

**Source columns.** `*_source` holds `;`-separated source IDs, plus these flags:
- `NF`: not found.
- `REGION_ONLY:<ids>`: the sources give only region-level information, so the cell is NA.
- `COUNT_ONLY:<ids>`: the sources give a number of districts but do not name them, so the cell is NA.
- `CONFLICT:<a>_vs_<b>`: the sources disagree, so the cell is NA.

**Inferred whole-region coverage.** Where a source gives a district count equal to the total for that region, the count is treated as whole-region coverage. These cases are listed under "Inferences" below.

## Coverage summary

These are district-years (out of 2,717).

| Variable | Known | NA | Non-zero |
|---|---|---|---|
| smc (main) | 2616 | 101 | 375 |
| smc_cycles | 2519 | 198 | 278 |
| smc_alt (public sources only) | 2554 | 163 | 408 |
| irs | 2676 | 41 | 233 |
| irs_month | 86 known for irs=1 (of 233) | | |
| itn_campaign (district-level) | 1749 | 968 | 190 |
| itn_campaign_region (region-level) | 2470 | 247 | 950 |
| vaccine | 2605 | 112 | 698 |

## Extra columns (beyond the requested set)

- **`smc_alt`, `smc_alt_cycles`, `smc_alt_source`**: SMC coded from public sources only.
  - The main `smc` column keeps the author's programme knowledge (source `AUTH`) that there is no SMC outside the five northern regions.
  - The two columns differ only in Oti and Bono East.
- **`itn_campaign_region`, `itn_month_region`, `itn_region_source`**: whether the region had a mass-campaign round that year (1), had none (0), or is unknown.
  - This is region-level information. It is kept separate so that it is not mistaken for district-level coverage.
  - `itn_campaign` is the strict district-level coding.

---

## Coding rules by intervention

### SMC
- **Year coding.** smc = 1 if the district received at least one SMC cycle in that calendar year (children 3-59 months, SP+AQ).
- **Cycles.** `smc_cycles` is the number of monthly cycles delivered (or planned, where noted). It is 0 when smc = 0.
- **Outside the five northern regions** (Upper West, Upper East, Northern, North East, Savannah), the main column has smc = 0 for every year (`AUTH`). See the contradiction with PMI below.
- **Rows of the main coding:**
  - **Upper West:**
    - 2015-2017: all 11 districts (GOGUE2020 Table 4). Cycles: 4 in 2015, 2 in 2016, 4 in 2017.
    - 2018: NA (region-level only).
    - 2019-2025: all 11 districts. The basis is COLE2026's statement that "since 2019, SMC has been implemented across all IRS districts", and every Upper West district is an IRS district.
    - Cycles 2021-2023: 4 (MOP23, MOP24, SMCALL). Other years: NA.
  - **Upper East:**
    - 2015: 0 (GOGUE2020; MOP16 says Upper West only).
    - 2016-2017: all districts (GOGUE2020 Table 3). Cycles: 2 in 2016, 4 in 2017.
    - 2018: NA.
    - 2019: the 3 IRS districts = 1 (COLE2026); the other districts NA.
    - 2020-2022: all districts. The basis is ADJEI2024UE ("SMC ... implemented in all districts of the region", 2020-2022) and GNA2020UE ("all Districts"). Cycles: 4.
    - 2023: all districts, 4 cycles (SMCALL: 69 districts = all 55 northern districts + Oti 9 + Bono East 5).
    - 2024: only the named districts. Bolgatanga had 5 rounds (GNA2024BOLGA). Kassena-Nankana East/West and Builsa North/South = 1 with cycles NA, because AYAMBA2025 says 4 and GHTIMES2025 says 5. All other districts NA.
    - 2025: all 15 districts in round 1 (GNA2025UE). Cycles NA.
  - **Northern, North East, Savannah:**
    - 2015-2018: 0. MOP16, MOP17 and MOP18 describe SMC in Upper West/Upper East only; MOP19 introduces the Northern expansion for 2019.
    - Tamale 2017-2018: NA (conflict with SAYIBU2025).
    - **2019:**
      - Savannah: all 7 districts, 4 cycles July-October (ADJEI2022SAV).
      - Northern and North East: only the PMI IRS districts (COLE2026; MOP19 "approximately 23 eligible districts (including all PMI-supported IRS districts)"), 4 cycles (MOP20), plus Tamale (SAYIBU2025).
      - Everything else: NA, because MOP19 gives only a count of about 23, unnamed.
    - **2020:** the PMI IRS districts (COLE2026) and Tamale (SAYIBU2025). Others NA (GHSC2021 is region-level).
    - **2021:** the same rule as 2020. Cycles: 3 in Northern Region and 4 in North East and Savannah (MOP23: "the Northern region was not able to complete a fourth cycle").
    - **2022:** all districts, 4 cycles (MOP24: "four cycles of SMC in 72 districts within seven regions", 27 Jun-9 Oct 2022).
    - **2023:** all districts, 4 cycles. MOP22 gives the CY2023 targets as "16 in Northern, seven in Savannah, six in North East", which equal the region totals; SMCALL confirms.
    - **2024:** all districts, 5 cycles. MOP23 gives the CY2024 targets; GHTIMES2025 quotes the Minister: "five cycles ... in the Upper East, North-East, Northern, Savannah, and Oti regions and five districts in the Bono East Region".
    - **2025:** all districts (MOP24, CY2025 targets). Cycles NA; Savannah 4 (PADFM2025).
- **`smc_alt` for Oti:**
  - 2015-2020: 0.
  - 2021: NA (MOP22/MOP23: SMC began "in Bono East and Oti regions in 2021"; region-level only).
  - 2022-2025: 1. The basis is MOP24 (72 districts in 7 regions), MOP22/MOP23/MOP24 (9 districts in Oti, i.e. the whole region; MOP22 says 11), and GNAKADJ2023/GNAKADJ2024 (Kadjebi, 4 cycles June-September 2023).
- **`smc_alt` for Bono East:**
  - 2015-2020: 0.
  - 2021-2025: NA, because it covers 5 of 11 districts and they are not named (COUNT_ONLY).
  - Exception: Sene East 2025 = 1 (MNM2025).

### IRS
- **Year coding.** irs = 1 if the district was sprayed in that year's campaign.
- **`irs_programme`:**
  - `PMI`: AIRS until 2017, VectorLink 2018-2023, Evolve 2024-2025.
  - `AGAMal/GF`: AngloGold Ashanti Malaria Control Ltd as Global Fund principal recipient.
  - `AGAMal`: AngloGold-funded, Obuasi.
  - `none`.
- **`irs_month`** is the spray window, start to end month.
- **PMI district lists** are complete for every year:
  - 2015-2016: 5 districts (6 units, because of the Bunkpurugu-Yunyoo split).
  - 2017-2019: 7 districts (8 units).
  - 2020-2023: 9 districts.
  - 2024-2025: 10 districts (adds Chereponi).
- **Zeros in the north.** Global Fund/AGAMal never sprayed in Northern, North East or Savannah (MOP18, MOP20, PROF24). So every district there that is not on the PMI list = 0.
- **Rest of the country = 0.** COLE2026 states "IRS has been centred in selected districts in northern Ghana ... and in Obuasi municipal and Obuasi East"; MOP18 and PROF24 give the same partner geography.

### ITN mass campaigns
- **`itn_campaign` = 1 when one of these holds:**
  - a source names the district;
  - a source states the whole region was covered (for example "all districts of the region", "all 26 districts", "all 18 districts");
  - a district count equals the region total after removing the excluded IRS districts.
- **`itn_campaign` = 0 when one of these holds:**
  - the district's region had no round that year;
  - the district was an IRS district in a round whose policy excluded IRS districts (2018, 2021, 2022, 2024: AFAG2022, PMD2018, MOP22, MOP23, MOP24, PROF24, GNA2021UE, DEPSOCOM2022).
- **NA otherwise.** In particular NA where a round happened in the region but only a region-level statement exists: MOP22/MOP23/MOP24 say "some urban centers are excluded", without naming them.
- **Continuous distribution.** This is national and not coded per district-year:
  - ANC: first visit.
  - CWC/EPI: at the second measles-rubella dose.
  - Primary-school distribution: classes 2 and 6, in non-campaign years and regions. Rounds in 2014, 2016, 2017, 2019, Nov-Dec 2020, 2022/23 and 2025-26.
  - Boarding senior high schools: from 2020.
  - Sources: MOP18 pp.30-31, MOP22 pp.36-37, MOP23, MOP24, NUNEZ2023. School distribution started nationwide in 2014 after a 2013 Eastern Region pilot (MOP16, MOP18).

### Malaria vaccine
- **Year coding.** vaccine = 1 if the district was vaccinating at any time in that year. Start dates:
  - Pilot: 30 Apr / 1 May 2019.
  - First expansion: 20 Feb 2023.
  - Second expansion: 25 Sep 2024.
- **`vaccine_product`:**
  - RTS,S for the pilot and the 2023 expansion.
  - `R21 or RTS,S (conflict)` for the 2024 expansion.
- **The 42 pilot districts.** They are read from the map in ADJEI2023PIE Fig 1 ("vaccinating / comparator / non-MVIP district"), overlaid on `units_simplified.geojson` (result: `scripts/data/malaria_vaccine_units.csv`; the columns fG, fY and fN are the colour fractions).
  - The overlay gives exactly 42 units.
  - Every unit in the seven pilot regions is at least 0.83 one colour; most are at least 0.94.
  - All 18 vaccinating districts named in the text of that paper (Fig 3) are among the 42.
  - **This is digitised from a map, not taken from a published list. It should be confirmed with GHS/EPI.** A direct check is also possible: the RTS,S DHIMS2 data elements were activated only in implementing districts (JALANGO2025).
- **Upper East is from text, not the map.** Only Kassena-Nankana East and West vaccinated during the pilot (ADJEI2024UE; PMC9666942).

---

## Source list

Retrieval dates are 2026-10-27. MOPs were retrieved from the Wayback Machine because pmi.gov is offline. The URL pattern is `https://web.archive.org/web/<ts>id_/https://www.pmi.gov/wp-content/uploads/<path>`.

### PMI and USAID documents
- **MOP16**: PMI. *Ghana Malaria Operational Plan FY 2016.* `2021/03/fy-2016-ghana-malaria-operational-plan.pdf`.
  - 2014-15 campaign months: Eastern/Volta Nov-Dec 2014; Western/Brong Ahafo Apr-May 2015.
  - 2014/15 campaign exclusions: Upper West, 5 Northern IRS districts and 1 Ashanti IRS district (unnamed).
  - SMC in Upper West only in 2015.
- **MOP17**: PMI. *Ghana MOP FY 2017.* `2021/03/fy-2017-ghana-malaria-operational-plan.pdf`. SMC in Upper West with plans for Upper East and Northern. The final campaign nets went to Greater Accra, Upper East and Northern by mid-2016.
- **MOP18**: PMI. *Ghana MOP FY 2018.* https://reliefweb.int/attachments/a45d2405-4ec7-3e3b-97fe-905c348d6c33/fy-2018-ghana-malaria-operational-plan.pdf
  - Campaign regions by year: 2014 Eastern and Volta; 2015 Ashanti, Brong Ahafo, Central, Western; 2016 Greater Accra, Upper East, Upper West, Northern.
  - "AGAMal reduced its coverage from 25 districts in 2014 to 10 districts in 2016 and 2017". The NMCP proposes IRS in "nine districts of the Upper West Region and Obuasi District".
  - PMI IRS in 2016 in 5 districts; 7 in 2017 (adds Gushegu and Karaga).
  - SMC in Upper West, "recently expanded to cover the Upper East"; Northern under discussion.
  - Obuasi district-wide IRS by AngloGold since 2005.
- **MOP19**: PMI. *Ghana Abbreviated MOP FY 2019.* `2021/03/fy-2019-ghana-abbreviated-malaria-operational-plan.pdf`. Expansion of SMC "to include approximately 23 eligible districts in Northern region".
- **MOP20**: PMI. *Ghana MOP FY 2020.* `2021/03/fy-2020-ghana-malaria-operational-plan.pdf`.
  - "AGAMal implements IRS in all nine districts in Upper West Region, three districts in the Upper East Region, and one district in Ashanti Region".
  - SMC in Northern, North East and Savannah July-October 2019, four rounds, about 297,000 children (PMI share).
  - The next mass campaign is "only in 2021"; highly urbanised areas (about 12% of the population) are excluded.
  - Durability monitoring of the June 2018 campaign in Zabzugu and Nanumba South.
- **MOP22**: PMI. *Ghana MOP FY 2022.* `2022/01/FY-2022-Ghana-MOP.pdf`.
  - SMC "in Bono East and Oti in 2021".
  - CY2023 SMC targets: "five districts in Bono East in addition to the 16 in Northern, seven in Savannah, six in North East, and 11 in Oti".
  - Table A-3: 2021 campaign regions (15; Upper West N/A); IRS districts excluded.
- **MOP23**: PMI. *Ghana MOP FY 2023.* `2023/01/FY-2023-Ghana-MOP.pdf`.
  - The 2021 SMC was "four cycles in six regions and three cycles in one region ... the Northern region was not able to complete a fourth cycle".
  - IRS expands from 9 to 10 districts; IRS district table for 2022-2024 (planned 2024 adds Chereponi).
  - "IRS districts and some urban centers are excluded from mass campaigns".
- **MOP24**: PMI. *Ghana MOP FY 2024.* `2024/04/FY-2024-Ghana-MOP-1.pdf`.
  - Table 1: PMI IRS 2023 in 9 named districts (preliminary: 372,603 structures, 93.4%); 2024-2025 planned 10 named (adds Chereponi).
  - 2022 SMC "four cycles ... in 72 districts within seven regions", 27 Jun-9 Oct 2022.
  - CY2025 SMC targets (5 Bono East, 16 Northern, 7 Savannah, 6 North East, 9 Oti, plus Upper East and Upper West), with a move to 5 cycles in "certain SMC districts".
- **PROF24**: PMI. *Ghana Malaria Profile FY 2024.* https://mesamalaria.org/wp-content/uploads/2025/04/GHANA_Malaria_Profile_PMI_FY_2024.pdf (p.18, Table 9).
  - Global Fund IRS in "Ashanti (2 districts), Upper East (3 districts), and Upper West (11 districts)"; PMI IRS in nine districts in North East and Northern.
  - The CY2024 ITN campaign is "nationwide, with the exception of some urban centers and all IRS districts".
  - SMC listed for "Bono East (5 districts), Northern, North East, Oti, Savannah, Upper East, Upper West".
  - Vaccine: 42 pilot districts, 51 comparator districts approved for 2022, 93 in total.
- **VL18**: PMI VectorLink Project. *Annual Report Oct 1 2017-Sep 30 2018.* Abt Associates. https://stacks.cdc.gov/view/cdc/146396
  - Table 4: 7 districts (Bunkpurugu-Yunyoo, East Mamprusi, Gushegu, Karaga, Kumbungu, Mamprugu Moaduri, West Mamprusi).
  - Dates: 24 Apr-29 May 2018 (6 districts) and 7 May-9 Jun 2018 (1 district).
- **VL19**: PMI VectorLink. *Annual Report Oct 2018-Sep 2019.* https://stacks.cdc.gov/view/cdc/146397. Table 4: 8 districts (Bunkpurugu-Nakpanduri, East Mamprusi, Gushegu, Karaga, Kumbungu, Mamprugu Moaduri, West Mamprusi, Yunyoo-Nasuan); 2 Apr-9 May 2019.
- **VL20**: PMI VectorLink. *Annual Report Oct 2019-Sep 2020.* https://stacks.cdc.gov/view/cdc/146398. Table 6: 9 districts (adds Tatale-Sanguli); 24 Mar-28 Apr 2020.
- **VL21**: PMI VectorLink. *Annual Report Oct 2020-Sep 2021.* https://stacks.cdc.gov/view/cdc/146399. Table 5: the same 9 districts; 23 Mar-4 May 2021.
- **VL22**: PMI VectorLink. *Annual Report Oct 2021-Sep 2022.* https://stacks.cdc.gov/view/cdc/146400.
  - Table 3: the same 9 districts; 2 Mar-12 Apr 2022.
  - The 2021 mass campaign distributed 16,139,502 nets. "The last 5,168,068 ITNs were distributed in Eastern and Greater Accra regions in October 2021-March 2022"; the same report's table says "Ashanti and Greater Accra".
- **VLF**: PMI VectorLink Project. *Final Report 2017-2023*, Sep 2023. https://stacks.cdc.gov/view/cdc/146401
  - Ghana annex p.A-15 and A-16.
  - 2022/23 spray: 381,151 structures, 1,021,269 people.
  - "2021 nationwide mass ITN campaign of 15.3 million nets in 15 regions".
  - June 2018 mass campaign in Zabzugu and Nanumba South.
- **EV3**: PMI Evolve Project. *Year 3 Annual Report, 1 Jan-31 Dec 2025.* Abt Global. https://mesamalaria.org/wp-content/uploads/2025/09/PMI-Evolve-Annual-Report-Year-3.pdf
  - §5.7: 10 districts (2020 list + Chereponi); 16 Jun-25 Jul 2025. The start "shifted from April to June due to the Stop-Work Order".
- **IAIA2019**: Aryeetey HNA. *USAID/Ghana environmental compliance field evaluation of PMI IRS.* IAIA 2019. https://conferences.iaia.org/2019/uploads/edited-presentations/aryeeytey%202.pdf. The 2015 campaign covered 5 Northern districts, 14 Apr-18 May 2015.
- **GHSC2021**: GHSC-PSM. *Preventing malaria in Ghana through SMC*, 22 Feb 2021. https://www.ghsupplychain.org/news/preventing-malaria-ghana-through-seasonal-malaria-chemoprevention. In 2020, 694,586 children in "PMI-supported Northern, North East, and Savanna regions". Region-level.

### Peer-reviewed papers
- **GOGUE2020**: Gogue C, Wagman J, Tynuv K, et al. An observational analysis of the impact of indoor residual spraying in Northern, Upper East, and Upper West Regions of Ghana: 2014 through 2017. *Malar J* 2020;19:242. doi:10.1186/s12936-020-03318-1 (PMC7353711).
  - Tables 2-4 give IRS, LLIN and SMC by district for 2014/15-2017.
  - Upper East: IRS suspended 2015-2016; reintroduced 2017 in Builsa North, Builsa South and Kasena-Nankana West, in August-September.
  - Upper West: IRS and SMC in all districts 2015-2017; SMC rounds 4, 2, 4.
  - Upper East SMC in all districts in 2016 (2 rounds) and 2017 (4 rounds).
  - IRS "typically ... around April and May".
- **COLE2026**: Coleman S, Atta-Obeng C, Nkolokosa C, et al. Malaria incidence rose following the introduction of neonicotinoid-based IRS in selected districts in northern Ghana. *PLOS Glob Public Health* 2026;6(4):e0005267. doi:10.1371/journal.pgph.0005267. Preprint: medRxiv doi:10.1101/2025.09.16.25335957 (read via https://www.medrxiv.org/content/early/2025/09/18/2025.09.16.25335957.source.xml).
  - 22 of 23 IRS districts 2015-2022: Upper West 11; North East 5 of 6; Upper East 3 of 15 (Builsa North, Builsa South, Kasena-Nankana West); Northern 4 of 17. Table 1 gives insecticide by district-year.
  - IRS is otherwise "centred ... in Obuasi municipal and Obuasi East".
  - SMC started in Upper West in 2015, Upper East in 2016, Northern and North East in 2019; "Since 2019, SMC has been implemented across all IRS districts".
- **ADJEI2024UE**: Adjei MR, Okine R, Tweneboah PO, et al. The impact of the RTS,S malaria vaccine on uncomplicated malaria: evidence from the phase IV study districts, Upper East Region, Ghana, 2020-2022. *Malar J* 2024. doi:10.1186/s12936-024-05123-6 (PMC11466024).
  - Kassena-Nankana East and West were "the only vaccinating areas in the region during the MVIP"; Builsa North and South were the comparators.
  - SMC "implemented in all districts of the region".
  - Table 1 IRS: Kassena-Nankana West 0/0/1, Builsa North 0/1/1, Builsa South 0/0/1, Kassena-Nankana East 0/0/0 (2020/2021/2022).
  - SMC doses: 3.0-4.0 out of 4.
- **ADJEI2024HEL**: Adjei MR, et al. Trend of RTS,S vaccine uptake in the MVIP pilot regions, Ghana; 2019-2022. *Heliyon* 2024;10:e38858 (PMC11490766). "Introduced in 42 out of 93 districts in Bono, Bono East, Ahafo, Central, Volta, Oti, and Upper East regions"; "the remaining (51) districts ... served as comparator sites".
- **ADJEI2023PIE**: Adjei MR, et al. Post introduction evaluation of the malaria vaccine implementation programme in Ghana, 2021. *BMC Public Health* 2023;23:586 (PMC10052308). Fig 1 is the map of vaccinating, comparator and non-MVIP districts (digitised, see above). Fig 3 names 18 vaccinating districts.
- **JALANGO2025**: Jalang'o R, Amponsa-Achiano K, Chisema M, Malm K, et al. Subnational introduction of the RTS,S/AS01E malaria vaccine into routine immunization: experience and lessons from the three pilot countries. *Malar J* 2025;24:244. doi:10.1186/s12936-025-05484-6 (PMC12305954).
  - 42 districts from the 30 Apr 2019 launch.
  - "On 20 February 2023, the introduction of the vaccine was expanded to the remaining 51 comparator districts".
  - RTS,S data elements were activated in DHIMS2 only for implementing districts.
- **PMC9666942**: Predictors of malaria vaccine uptake among children 6-24 months in the Kassena Nankana Municipality. *Malar J* 2022. doi:10.1186/s12936-022-04378-1. "Kassena Nankana Municipality is among the only two selected implementing areas in Upper East".
- **ADJEI2022SAV**: Adjei MR, Kubio C, et al. Effectiveness of SMC in reducing under-five malaria morbidity and mortality in the Savannah Region, Ghana. *Ghana Med J* 2022;56(2). doi:10.4314/gmj.v56i2.2 (PMC10336463). "All seven districts in Savannah Region"; SPAQ monthly, four times, July-October; SMC was the only new tool introduced in the region in 2019.
- **AYAMBA2025**: Ayamba EY, Dzotsi EK, et al. Evaluation of SMC implementation in the Upper East region of Northern Ghana. *Malar J* 2025;24:123. doi:10.1186/s12936-025-05322-9 (PMC12001400). Four Upper East districts; 4 cycles (2024).
- **NONVIGNON2016**: Nonvignon J, et al. Cost-effectiveness of SMC in Upper West Region of Ghana. *Malar J* 2016;15:367. doi:10.1186/s12936-016-1418-z. All Upper West districts, 2015, 4 rounds. The paper gives the window as July-November in one place and June-September in another.
- **SAYIBU2025**: Sayibu SS, et al. *J Interv Epidemiol Public Health* 2025;8 Suppl 12:9. doi:10.37432/jieph.supp.2025.8.2.12.11. Tamale: SMC July-October 2019 and 2020, July-September 2021. It also reports SMC coverage for Tamale in July 2017 and July 2018 (conflict).
- **YUK2022**: Yukich J, et al. Incremental cost and cost-effectiveness of IRS with pirimiphos-methyl ... NgenIRS. *Malar J* 2022 (PMC9188086). Table 1: AGAMal Actellic districts were 13 in 2017 and 10 in 2018. These count Actellic districts only, not all sprayed districts.
- **AFAG2022**: Afagbedzi SK, Alhassan Y, Guure C. Impact evaluation of LLIN distribution campaign on malaria cases ... in Ghana. *Malar J* 2022;21:370. doi:10.1186/s12936-022-04393-2 (PMC9720946).
  - "During the first half of 2016, the PMD of LLIN was conducted in Upper West and Northern regions".
  - The 2018 campaign "ended in December 2018 with about 15.5 million LLINs distributed in 194 districts in nine out of the country's 10 regions", excluding Upper West and IRS areas.
- **NUNEZ2023**: Nuñez L, Skjefte M, et al. Successful implementation of ITN distribution through health facilities in Ghana. *Malar J* 2023;22:224. doi:10.1186/s12936-023-04592-5 (PMC10398947). Covers the ANC and CWC channels.

### Programme, NGO and other reports
- **IVCC2019**: IVCC/Unitaid NgenIRS. *Evidence snapshot: 3GIRS in northern savannah, Ghana*, Dec 2019. https://www.ivcc.com/wp-content/uploads/2020/01/NgenIRS-Evidence-Ghana-IRS-FactSheet.pdf. IRS was suspended in all Upper East districts in 2015.
- **PMD2018**: GHS/NMCP. *Draft plan for 2018 LLIN point mass distribution campaign*, 1 May 2018. https://files.givewell.org/files/DWDA%202009/AMF/AMF_Ghana2018_Distribution_Plan_ver14May18.pdf
  - Phase 1: Eastern, Volta, Brong Ahafo, Western, Central. Phase 2: Ashanti, Northern, Upper East, Greater Accra.
  - "Areas benefiting from the IRS program will not be included".
- **AMFAGR2016**: GHS-AMF distribution agreement, 2016. https://files.givewell.org/files/DWDA%202009/AMF/AMF_Ghana_2016_distribution_agreement.pdf. Greater Accra "(excluding the Metropolitan District)".
- **AMF200**, **AMF203**, **AMF204**: Against Malaria Foundation distribution pages, https://www.againstmalaria.com/Distribution.aspx?ProposalID=200 (Northern, April 2016, all 26 districts), ProposalID=203 (Upper West, September 2016, all 11 districts) and ProposalID=204 (Greater Accra, July 2016, 12 districts).
- **ERD2016**: Episcopal Relief & Development/ADDRO. *Activity Report 4 (Sep 2016)* and *Upper West pre-distribution and distribution report (Dec 2016)*, on files.givewell.org under /files/DWDA 2009/AMF/. Monitored the Upper West distribution in September 2016.
- **SMCALL**: SMC Alliance, Ghana country page. https://www.smc-alliance.org/countries/ghana-0
  - 2023: 4 cycles in 69 districts, June to November/December, 1,497,595 children.
  - 2024: 5 cycles June-November, 1,549,854 children targeted.

### News (GNA = Ghana News Agency)
- **CITI2017**: Citi FM, 22 Apr 2017. https://citifmonline.com/?p=312971. PMI 2017 IRS in 7 named districts, 25 Apr-29 May.
- **BG2019**: BusinessGhana/GNA, 16 Jun 2019, "AngloGold Ashanti Malaria Control completes 2019 IRS campaign". https://www.businessghana.com/site/news/General/189408/. 16 districts: Obuasi Municipal, Obuasi East, Kasena Nankana West, Builsa North and "Bulsa West" (= Builsa South), and all 11 Upper West districts. Dates printed "15th March, 2018 ... 31st May 2019"; read as 15 Mar-31 May 2019.
- **JOY2022**: MyJoyOnline, 30 Apr 2022. https://www.myjoyonline.com/agamal-to-sustain-interventions-for-malaria-control-in-obuasi/. AGAMal IRS in 16 districts: Obuasi Municipal, Obuasi East, 11 Upper West, 3 Upper East.
- **GNA2024IRS**: GNA, 14 Jun 2024. https://gna.org.gh/2024/06/us-supports-insecticide-spraying-campaign-in-northern-regions/. PMI 2024 IRS in "10 districts in the Northern and North East Regions" (only Kumbungu named).
- **GNA2024AGA**: GNA, 26 Apr 2024. https://gna.org.gh/2024/04/anglogold-ashanti-well-continue-to-be-resolute/. AGAMal covers "16 districts in the Ashanti, Upper West and East regions".
- **GNA2020UE**: GNA, 25 Jul 2020. https://gna.org.gh/2020/07/ghs-to-administer-anti-malaria-drugs-to-244199-children-in-upper-east/. SMC in "all Districts" of Upper East.
- **GNA2022UE**: GNA, 8 Oct 2022. https://gna.org.gh/2022/10/ghana-health-service-exceeds-malaria-chemoprevention-target-in-upper-east-region/. Four rounds, 27 Jun-25 Sep 2022. SMC began in Upper West in 2015 and Upper East in 2016.
- **GNA2024BOLGA**: GNA, 3 Jul 2024. https://gna.org.gh/2024/07/seasonal-malaria-chemoprevention-takes-off-in-bolgatanga/. Bolgatanga: "five rounds"; round 1 ran 2-8 Jul 2024.
- **GNA2025UE**: GNA, 17 Jul 2025. https://gna.org.gh/2025/07/ghs-doses-252755-children-in-smc-exercise-in-upper-east/. Round 1, 2-6 Jul 2025; all 15 districts reported.
- **GNAKADJ2023**: GNA, Jun and Nov 2023. https://gna.org.gh/2023/06/kadjebi-starts-smc-exercise-on-june-26/ and https://gna.org.gh/2023/11/kadjebi-ghs-exceeds-smc-registration-dosing-target/. Kadjebi (Oti): SMC in four rounds, June-September 2023.
- **GNAKADJ2024**: GNA, Jul 2024. https://gna.org.gh/2024/07/parents-advised-to-dose-children-against-malaria/. Kadjebi SMC cycle 1, 2-8 Jul 2024.
- **GHTIMES2025**: Ghanaian Times, 28 Apr 2025. https://ghanaiantimes.com.gh/ghana-reduces-malaria-related-deaths-by-97-2014-2024-health-minister/. Minister: 2024 SMC reached "over 1.9 million children through five cycles ... in the Upper East, North-East, Northern, Savannah, and Oti regions and five districts in the Bono East Region".
- **PADFM2025**: PAD FM, 9 Jul 2025. https://padfm.com.gh/2025-seasonal-malaria-chemoprevention-smc-immunization-begins-in-savannah-region/. Savannah 2025: 4 cycles, round 1 on 9-13 Jul.
- **MNM2025**: Malaria No More, "In Ghana, one volunteer is using his tricycle ...". https://www.malarianomore.org/story/in-ghana-one-volunteer-is-using-his-tricycle-to-build-trust-in-malaria-prevention. SMC in Kajaji, Sene East (Bono East), probably 2025; Bono East target 105,946 children.
- **THECOP2019**: thecophq.org, 20 Jul 2019. https://thecophq.org/ghs-to-administer-new-anti-malaria-drug-to-children. Northern Region SMC 22-28 Jul 2019, 68,983 children targeted. Used only in the notes: the small target suggests partial coverage.
- **CITI2018VOLTA**: Citi Newsroom, 25 Mar 2018. https://citinewsroom.com/2018/03/v-r-moh-partners-to-distribute-1-million-mosquito-nets/. Volta (incl. today's Oti), 25 districts, 27-29 Mar and 3-6 Apr 2018.
- **CITI2018ASH**: Citi Newsroom, 13 Nov 2018. https://citinewsroom.com/2018/11/ashanti-region-ghs-to-begin-distribution-of-insecticide-treated-nets/. Ashanti, 15-21 Nov 2018.
- **GNA2021UE**: GNA, 8 Apr 2021. https://gna.org.gh/?p=155256. Upper East registration 7-13 Apr 2021 in 12 of 15 districts; Kassena-Nankana West, Builsa North and Builsa South excluded (IRS).
- **GNA2021VOLTA**: GNA, 20 Oct 2021. https://gna.org.gh/2021/10/more-than-a-million-mosquito-nets-to-be-distributed-in-volta/. Volta distribution 29 Nov-5 Dec 2021.
- **DEPSOCOM2022**: DEPSOCOM, 4 Feb 2022. Ashanti registration 5-11 Feb 2022, excluding Obuasi and Obuasi East (IRS). Reported by the research pass; not re-fetched.
- **GNA2022ASH**: GNA, 28 Feb 2022. https://gna.org.gh/?p=200176. Ashanti distribution began 28 Feb 2022; five districts "would have their turn later" (Asante-Akim South, Adansi South, Adansi North, Ahafo Ano South, Amansie South).
- **GNA2024VOLTA**: GNA, 9 Apr 2024. Volta distribution 11-15 Apr 2024, all 18 districts. Reported by the research pass.
- **GNA2024CEN**: GNA, 3 May 2024. https://gna.org.gh/2024/05/central-region-to-distribute-1-6-million-mosquito-nets-from-may-9/. Central, 9-13 May 2024, "across all districts of the region".
- **GNA2024BONO**: GNA ?p=356234 and ghanadistricts.com. Bono and Ahafo distribution 23-27 May 2024. **Search snippets only**; used at region level only.
- **GNA2024ASH**: GNA, 6 Jun 2024. https://gna.org.gh/2024/06/household-registration-begins-ahead-of-mass-distribution-of-mosquito-nets-in-ashanti-region/. Registration 7-11 Jun 2024 in "41 districts"; distribution 18-22 Jul 2024 (GNA 18 Jul 2024).
- **GNA2024KADJ**: GNA, 27 Jun 2024. Kadjebi ITN distribution 13-17 Aug 2024.
- **ADOM2025**: Adom Online, 6 Apr 2025. https://www.adomonline.com/ghs-to-begin-registration-mass-distribution-of-mosquito-nets-from-april-9/. Accra Metro registration 9-13 Apr 2025; distribution 2-6 May 2025.
- **GNA2025TEMA**: GNA, 9 Apr 2025. https://gna.org.gh/2025/04/tema-health-directorate-begins-registration-for-free-insecticide-nets/. Tema registration in April 2025; distribution date to be announced.
- **UNICEF2024**: UNICEF Ghana, press release, 25 Sep 2024. https://www.unicef.org/ghana/press-releases/ghana-expands-malaria-vaccine-rollout. R21/Matrix-M in 43 districts of Upper West, Northern, Savannah and Western North; "11 out of 16 regions"; the remaining districts 2025-2029.
- **GRAPHIC2024**: Daily Graphic, 30 Sep 2024. https://www.graphic.com.gh/news/general-news/ghana-news-eliminating-child-malaria-ghs-rolls-out-new-vaccines-in-136-districts.html. RTS,S in 136 districts (93 + 43); "pilot ended on 31 December 2023".
- **GNA2025VAX**: GNA, May 2025. https://gna.org.gh/2025/05/ghana-records-45-per-cent-reduction-in-malaria-among-children-under-five/. Dr Malm: R21 "deployed in 43 malaria-endemic districts".
- **GAVI2024**: Gavi VaccinesWork, 22 Mar 2024. https://www.gavi.org/vaccineswork/ghana-sees-falling-malaria-burden-targets-elimination. "All 93 districts located in these regions".
- **AUTH**: author's programme knowledge. There is no SMC for under-fives outside the five northern regions.

---

## Contradictions with the earlier working assumptions

1. **There is SMC outside the north.** The main coding (`AUTH`) has none, but the following public sources contradict it:
   - PMI FY2024 profile (PROF24): lists "Bono East (5 districts) ... Oti".
   - MOP22 and MOP23: SMC began "in Bono East and Oti regions in 2021".
   - MOP22, MOP23 and MOP24: SPAQ targets for 5 Bono East districts and 9 (or 11) Oti districts for CY2023-2025.
   - GNAKADJ2023 and GNAKADJ2024: Kadjebi (Oti) with 4 SMC rounds for children 3-59 months, June-September 2023.
   - GHTIMES2025: the Minister lists Oti and five Bono East districts in 2024.
   - MNM2025: Sene East.

   These are coded in `smc_alt`. The main column is kept as instructed. Oti and Bono East are in the forest/transition belt, and the sources describe these districts as highly seasonal.
2. **SMC start years.**
   - Upper West 2015 is confirmed (GOGUE2020, NONVIGNON2016, GNA2022UE).
   - Upper East 2016 is confirmed.
   - "Northern 2019" holds only in part:
     - Savannah: whole region in 2019 (ADJEI2022SAV).
     - Northern and North East: only "approximately 23 eligible districts" in 2019 (MOP19). The Northern Region target was only 68,983 children (THECOP2019).
     - Whole-region coverage of Northern, North East and Savannah is documented from 2022.
   - Graphic (2014) reports only the policy adoption. "2016" (Ayamba 2025, MOP21) refers to national adoption or to the Upper East start.
   - SAYIBU2025 reports SMC coverage in Tamale in 2017-2018, which conflicts with every MOP.
3. **The SMC calendar is not always June-September with 4 cycles.**
   - 2015 Upper West: July-November (NONVIGNON2016).
   - 2016: 2 rounds only in both Upper West and Upper East (GOGUE2020). Upper East announced 4 phases, Aug-Nov (Citi FM/Graphic, Aug 2016).
   - 2019-2021 Northern regions: July-October (MOP20, ADJEI2022SAV).
   - 2021: 3 cycles in Northern Region (MOP23).
   - 2022: 27 June-9 October (MOP24).
   - 2023: June to November/December (SMCALL).
   - 2024: 5 cycles (SMCALL; GHTIMES2025; GNA2024BOLGA). AYAMBA2025 gives 4 in 4 Upper East districts.
   - 2025 planned: 5 cycles in "certain" districts (MOP24).
4. **"Southern districts do not get SMC because transmission is perennial."** This is contradicted for Oti and part of Bono East from 2021 (item 1).
5. **IRS conflicts.**
   - Upper East 2020-2021: COLE2026 Table 1 marks Builsa North, Builsa South and Kasena-Nankana West as sprayed. ADJEI2024UE (Upper East regional data) shows no IRS there in 2020, and only Builsa North in 2021. These cells are NA.
   - AGAMal district counts: 10 in 2016-2017 (MOP18) and 13 or 10 in 2017-2018 (YUK2022, Actellic districts only), against 11 Upper West + 3 Upper East + Obuasi (GOGUE2020, COLE2026). Coded from the district-named sources.
   - 2024 IRS total: 28 districts (Graphic, 28 Apr 2025) against PMI 10 + Global Fund 16 = 26.
   - PMI 2019: VLF says "nine districts up from seven" during the project. VL19 reports 8 in 2019, and the ninth (Tatale-Sanguli) came in 2020.
6. **ITN conflicts.**
   - Upper West 2016 timing: "first half of 2016" (AFAG2022) against September 2016 (AMF203, ERD2016). Coded September.
   - MOP16 and MOP17 say Upper West was excluded from the 2014-16 round; MOP18 says it was included in 2016.
   - The 2021 Ashanti round was delivered in Feb-Mar 2022, so it is coded in 2022.
   - VL22 names "Ashanti and Greater Accra" in one place and "Eastern and Greater Accra" in another for Oct 2021-Mar 2022.
7. **Vaccine conflicts.**
   - The 2024 product is R21 per UNICEF2024 and GNA2025VAX, but RTS,S per GRAPHIC2024. Coded `R21 or RTS,S (conflict)`.
   - The launch-day press gave "33 districts in six regions" (Graphic, 30 Apr 2019). Later sources say 42 in 7 regions.
   - The comparator districts were **not** vaccinated in 2021-2022 despite the October 2021 WHO recommendation. They started on 20 Feb 2023 (JALANGO2025).

## Assumptions and inferences (each flagged in the source column)

- **Whole region inferred from a district count equal to the region total:**
  - Global Fund IRS in Upper West, "11 districts", 2023-2024 (PROF24).
  - SMC in Northern 16, Savannah 7, North East 6 and Oti 9 (MOP22, MOP23, MOP24), and 72 or 69 districts in total (MOP24, SMCALL).
  - Vaccine 2023: 93 = all districts of the 7 MVIP regions; 2024: 43 = all districts of Upper West, Northern, Savannah and Western North.
  - Ashanti ITN 2024: "41 districts" = 43 minus the 2 IRS districts.
- **The UW and UE IRS districts in 2023-2024** come from PROF24's counts (UE 3, Ashanti 2), with the names taken from COLE2026, BG2019 and JOY2022.
- **PMI 2024 IRS districts** are the MOP24 planned list of 10 names, consistent with GNA2024IRS's count of 10. There is no end-of-spray report for 2024, and no 2023 or 2024 spray months.
- **SMC in Upper West 2019-2025 and in the IRS districts of Upper East, Northern and North East** rests on COLE2026's general statement "since 2019 ... across all IRS districts".
- **Obuasi 2016-2017** rests on MOP18 (AGAMal's 10 districts in 2016-2017 = Upper West 9 old districts + Obuasi; Obuasi IRS district-wide since 2005). This is an inference from MOP18's wording.
- **2017 ITN = 0 everywhere**, although MOP20 Fig A14 lists 202,725 "mass campaign" nets in a 4-district NetApp pilot in 2017 (districts unnamed).
- **2019, 2020 and 2023 ITN = 0** (no mass round). School and ANC/CWC distribution continued.
- **Pilot vaccine districts** are digitised from a map (see the vaccine rules above).

## The 5 most important gaps

1. **SMC 2018-2021 below region level.**
   - Upper West and Upper East 2018: NA.
   - Northern and North East 2019-2021: only the IRS districts and Tamale are known; the 2019 list of about 23 Northern districts is not published.
   - Cycles for 2019-2020 and 2025 are mostly NA.
   - A DHIMS2 SMC dataset (cycles by district) would close this gap directly.
2. **ITN mass-campaign months by district** (968 NA district-years).
   - 2015: region-level only.
   - 2018: months known only for Volta/Oti, Ashanti, Zabzugu and Nanumba South.
   - 2021: months known only for Upper East and Volta; urban exclusions unnamed.
   - 2024: Eastern, Western, Western North, Bono East, the northern regions and most of Greater Accra are unknown.
   - 2025 is largely unknown.
3. **Bono East SMC districts.** Five of 11 districts from 2021 are unnamed, apart from Sene East. Oti 2021 is also only region-level.
4. **IRS gaps:**
   - All Global Fund/AGAMal districts in 2025 (no 2025 source found).
   - Obuasi and Obuasi East in 2015, 2018, 2020 and 2021.
   - The conflicting Upper East cells in 2020-2021.
   - Spray months for 2016, 2023 and 2024 (PMI) and for most AGAMal years.
5. **Vaccine:**
   - The pilot district list is map-derived and needs GHS/EPI confirmation.
   - 2025 status of the never-covered regions (North East, Ashanti, Eastern, Western, Greater Accra) is NA; no 2025 expansion was found.
   - The product for the September 2024 phase is contested.

## District-name matching notes

- **Bunkpurugu-Yunyoo** (split 2018 into Bunkpurugu-Nakpanduri and Yunyoo-Nasuan). It is listed as one district in 2015-2018 (PMI) and mapped to both units, `bunkpurugunakpanduri` and `yunyoonasuan`.
- **Savelugu-Nanton** (split 2018 into `savelugu` and `nanton`). Not sprayed 2015-2025.
- **Tolon-Kumbungu** split in 2012. Kumbungu is sprayed; Tolon is not.
- **Garu-Tempane** (Gogue tables) maps to `garu` and `tempane`. **Bolgatanga** (Gogue tables, pre-2018) maps to `bolgatanga` and `bolgaeast`.
- **Kassena / Kasena-Nankana.**
  - The prose in GOGUE2020, IVCC2019 and the ASTMH poster says "Kassena". GOGUE2020 Table 3, COLE2026 and BG2019 specify Kasena-Nankana West, so the unit is `kasenanankanawest`.
  - "Kasena-Nankana" in Gogue Table 3 and "Kassena Nankana Municipality" map to `kasenanankanaeast`.
- **Builsa South** appears as "Bulsa West" in BG2019.
- **Upper West redistricting.** Nandom (from Lawra) and Daffiama-Bussie-Issa (from Nadowli-Kaleo) were created in 2012-2014. "Nine districts of Upper West" in MOP18 and MOP20 uses the old delineation and equals all 11 current units.
- **Obuasi East** was carved from Obuasi Municipal around 2018. Sources before that which mention "Obuasi" cover both `obuasi` and `obuasieast`.
- **Old Northern Region** (Northern + Savannah + North East, split 2019): the AMF 2016 "all 26 districts" maps to all 29 current units in these three regions.
- **Brong Ahafo** became Bono, Bono East and Ahafo. **Volta** became Volta and Oti. **Western** became Western and Western North. These splits happened in 2019; 2015-2018 region-level statements are applied to all the successor regions.
- **The "Hohoe + Guan" unit** (Volta) contains Guan, which is in Oti. Oti SMC (`smc_alt`) is therefore not applied to it. Vaccine: the unit maps as comparator (2023 start).
- **Spelling variants:** Tatale-Sanguli / Tatale-Sangule (`tatalesanguli`); Mamprugu Moaduri / Moagduri / Moadori (`mamprugumoagduri`); Gushiegu / Gushegu (`gushegu`).
- **Single units:** Kumasi, Accra Metro and Tema are each one unit. District-level statements about sub-metropolitan districts were not found, except Kpone-Katamanso (separate unit; 2021 news snippet, not coded).
