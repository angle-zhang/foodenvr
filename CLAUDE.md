# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## RULES
**YOU MUST FOLLOW THESE RULES THEY ARE NON-NEGOTIABLE**

1. WRITE SIMPLE, HUMAN-READABLE CODE WHEN POSSIBLE, AVOIDING COMPLEX PROCEDURES WHEN SIMPLE ONES MAY BE POSSIBLE WITH JUST A FEW MORE LINES OF CODE

2. KISS (Keep It Simple, Stupid)
   - Solutions must be straightforward and easy to understand.
   - Avoid over-engineering or unnecessary abstraction.
   - Prioritise code readability and maintainability.

3. YAGNI (You Aren't Gonna Need It)
   - Do not add speculative features or future-proofing unless explicitly required.
   - Focus only on immediate requirements and deliverables.
   - Minimise code bloat and long-term technical debt.

4. Principles: Single Responsibility, Open-Closed, Liskov Substitution, Interface Segregation, Dependency Inversion.

---

## Project Overview

R-based geospatial research project studying food environment access and Latino health outcomes in Los Angeles County. The pipeline calculates network-based food accessibility measures (via `r5r` + OpenStreetMap) for LA County households and census tracts, then links those to health outcome data from the El Sendero Latino Health study.

---

## Setup — `0_Libraries.R`

**Run first.** All numbered scripts begin with `source("0_Libraries.R")`. Working directory must be the repo root.

```r
source("1_data_collection.R")          # run from repo root
rmarkdown::render("3_prelim_results.Rmd")
```

**Key configuration:**
- `options(java.parameters = "-Xmx12G")` must be set **before** `library(r5r)` — changing it requires restarting R.
- On SSI lab computers, use `rJavaEnv` to install Java 21. On personal machines, set `JAVA_HOME` manually.
- Shared data paths (outside repo, not git-tracked):
  - `base_path` → `../0_shared-data/food-environment-measures/raw/`
  - `processed_path` → `../0_shared-data/food-environment-measures/processed/`
  - `access_path` → `processed_path/LAC_accessibility`

**Sources automatically:** `helper/data_functions.R`, `helper/get-food-data.R`, `helper/get-la-county-admin-data.R`, `helper/universal_variables.R`

**Does NOT source:** `helper/gen-helper.R` — sourcing it has immediate side effects (initialises r5r JVM, reads `foodpoi.csv`). Scripts that need it source it explicitly.

---

## Step A — Data Collection

**File:** `1_data_collection.R`

### Functions & Sequence

1. `get_county_boundary(proj_crs)` → `st_buffer(..., proj_buffer_size)` → `st_bbox()` — builds LAC boundary, 30-mile buffer, and bounding box used to clip downloads.
2. `download_dem(path, boundary, county)` — downloads elevation raster via `elevatr`, saves as `.tif`.
3. `download_osm(place_name="Southern California", bbox, county)` — downloads OSM road network via `osmextract` as `.pbf`/`.gpkg`. Uses Southern California extract (larger than county) clipped by bbox.
4. `download_census_tracts(state, county, year, land=TRUE)` — fetches tracts via `tigris`, filters `ALAND > 0` (land-only), saves `.gpkg`.
5. `download_census_blocks(state, county, year, land=TRUE)` — same pattern for blocks.
6. `save_naics(processed_path)` — downloads NAICS food category classification from a Google Sheet and saves as `naics.csv`.

### Inputs
- Internet + API access: ArcGIS REST (county boundary), `elevatr`, `osmextract`, `tigris`, Google Sheets (requires `googlesheets4` auth).
- `proj_buffer_size` from `universal_variables.R` (30 miles in feet, matching `proj_crs` units).

### Outputs
| File | Location |
|------|----------|
| `{county}_dem.tif` | `base_path/geo_{county}/` |
| `geofabrik_socal-latest.osm.pbf` (or `.gpkg`) | `base_path/geo_{county}/` |
| `CA_Los Angeles_{year}_census_tracts.gpkg` | `base_path/geo_{county}/` |
| `CA_Los Angeles_{year}_census_blocks.gpkg` | `base_path/geo_{county}/` |
| `naics.csv` | `processed_path/` |

### Known Issues
- `save_data_axle()` and `download_foodins_lacounty_ssi()` are commented out — Data Axle POI data is licensed and must be obtained separately, then placed in `processed_path/food_environment/`.
- OSM download covers all of Southern California; the `.pbf` is large and slow to convert to `.gpkg` on first read.

---

## Step B1 — Clean POI Data

**Files:** `1_data_cleaning.R` (script), `helper/get-food-data.R` (functions), `helper/geo-duplicate-finder.R` (function)

### Functions & Sequence

1. `get_county_boundary()`, `st_buffer()` — re-derive study area boundary for clipping.
2. `get_census_tracts()`, `get_census_blocks()` — load previously saved `.gpkg` files.
3. `save_and_clean_foodpoi(year, state, processed_path, boundary)` (in `get-food-data.R`):
   - `get_data_axle(year, state)` — reads licensed Data Axle CSV from `processed_path/food_environment/`.
   - `get_naics(processed_path)` — reads `naics.csv` (NAICS code → food category mapping, columns: `code`, `zhang-2025`).
   - Truncates NAICS to 6 digits, joins on `code`, `dcast()` to wide format with one binary column per category.
   - `find_geo_duplicates(foodpoi, name_col="COMPANY", max_dist_m=80, jw_threshold=0.9)` — identifies likely duplicates using Jaro-Winkler name similarity and spatial proximity; returns deduplicated data.
   - Writes `foodpoi_{year}.csv`.
4. `get_foodpoi()` — loads saved `foodpoi_{year}.csv` for inspection.

The NAICS classification scheme is defined in the Google Sheet at the URL stored in `save_naics()`. Categories: `CNV`, `FF`, `GRC`, `RR`, `SMK`, `SPF`, `Not.included`.

### Inputs
- `processed_path/food_environment/{year}_data_axle_{state}.csv` — **must be obtained manually** (licensed).
- `processed_path/naics.csv` — from Step A.

### Outputs
| File | Location | Columns |
|------|----------|---------|
| `foodpoi_{year}.csv` | `processed_path/` | `id, COMPANY, ADDRESS.LINE.1, CITY, ZIPCODE, LATITUDE, LONGITUDE, CNV, FF, GRC, RR, SMK, SPF, Not.included` |

### Known Issues
- Much of the chain-name cleaning code in `1_data_cleaning.R` is commented out — POI cleaning is handled by `save_and_clean_foodpoi()` in the helper, not by the script body.
- `find_geo_duplicates()` has hardcoded debug assignments at the top of the function body (not yet refactored to pure function).

---

## Step B2 — Prepare Population Representation Points

**Files:** `helper/get-la-county-admin-data.R` (functions), called from `1_data_cleaning.R` and `2_gen_measures.R`

Three origin types are prepared here. Each has a `download_*` / `calc_*` function (run once) and a `get_*` function (used in pipeline scripts).

### CT Centroids & Pop-Weighted Centroids

`calc_and_save_lac_centroids(la_ct, la_cb, proj_crs, processed_path)` — **run once:**
1. `st_centroid()` on census tract polygons → unweighted centroids.
2. `calc_pop_weighted_centroid(la_cb, 'TRACTCE20', 'POP20')` (in `data_functions.R`) — derives population-weighted centroid from census block centroids weighted by `POP20`.
3. Merges weighted centroids back onto tract attributes; drops tracts with no population (`st_is_empty()`).
4. Writes both to `processed_path/LAC_origins/`.

`get_lac_centroids(path, county)` / `get_lac_weight_centroids(path, county)` — read saved `.gpkg` files.

### Household Parcels

`download_lac_households(path, processed_path, proj_crs)` — **run once:**
- Unzips parcel GDB, reads layer `LACounty_Parcels_SpatialJoin_20_10_102424`.
- Filters: `is.na(EXCLUDE) & UseType == "Residential"`. The `EXCLUDE` column flags ~107K parcels to omit.
- Adds sequential `id` column (required by r5r), converts `GEOID_20` to character.
- Writes to `processed_path/LAC_origins/la_hh_cleaned.gdb`.

`get_lac_households(processed_path, proj_crs)` — reads `.gdb` and prepends `"0"` to `GEOID_20` to restore the full 11-digit FIPS string.

### Inputs
- `base_path/ParcelData_031325_LACountyParcelsAsHH_export.gdb.zip` — manual download required.
- Census tracts and blocks from Step A.

### Outputs
| File | Location |
|------|----------|
| `{county}ctcent_dat.gpkg` | `processed_path/LAC_origins/` |
| `{county}ct_wtcent_dat.gpkg` | `processed_path/LAC_origins/` |
| `la_hh_cleaned.gdb` | `processed_path/LAC_origins/` |

### Known Issues
- `GEOID_20` in the raw GDB is stored as numeric, dropping the leading zero — `get_lac_households()` restores it with `paste0("0", ...)`.
- Census blocks with `POP20 == 0` are excluded from weighted centroids; their parent tracts get no weighted centroid point.
- `calc_and_save_lac_centroids()` is commented out in `1_data_cleaning.R` — uncomment and run once when census data changes.

---

## Step C — Accessibility Computation

**Files:** `2_gen_measures.R`, `helper/gen-helper.R` (sourced explicitly)

### Functions & Sequence

1. `source("./helper/gen-helper.R")` — **triggers two immediate side effects:**
   - `setup_r5(data_path)` initialises the r5r JVM (data_path = `base_path/geo_{county}`). JVM can only be initialised once per R session — restart R to change settings.
   - Reads `foodpoi.csv` from `processed_path` into the `foodpoi` sf object (destinations).
2. Load and filter origins:
   - `get_lac_households()` → filter by `GEOID_20 %in% la_city_ct$GEOID` → `la_city_hh`
   - `get_lac_centroids()` → add `id`, `lon`, `lat` columns → `la_ctcent_dat`
   - `get_lac_weight_centroids()` → merge with `la_ct_key`, add `lon`, `lat` → `la_ct_wtcent_dat`
3. Build and save `la_ct_key` (id ↔ GEOID mapping) to `processed_path/LAC_origins/la_ct_key.csv`.
4. `compute_accessibility(origins, destinations, mode, chunk_size, cutoffs, colnames, origin_type, output_path)` for each origin type.

**`compute_accessibility()` internals:**
- Constructs output filename: `{origin_type}_{mode}{departure_time_formatted}[_{file_id}].csv`.
- Loops in chunks of `chunk_size` rows; calls `r5r::accessibility()` per chunk.
- Appends each chunk to the output CSV via `write.table(..., append=TRUE)`.
- Sets `last_idx <<-` (global) to allow resuming an interrupted run.
- Calls `rJava::.jgc()` after each chunk to force JVM garbage collection.

`calc_chunk_size(ram, mode)` — estimates chunk size: ~2,000 origins for CAR, ~1,000,000 for WALK at 128 GB RAM; scales linearly with available RAM.

### Inputs
- `base_path/geo_Los Angeles/` — OSM `.pbf`/`.gpkg` + DEM `.tif` (required by `setup_r5()`).
- `processed_path/foodpoi_{year}.csv` — destinations (read at source time in `gen-helper.R`).
- Household and centroid files from Step B2.
- `processed_path/LAC_origins/la_ct_key.csv` — GEOID key.

### Outputs
Chunked CSVs appended to `access_path/density/la_city/CATG/`:

| Pattern | Origin type |
|---------|-------------|
| `ct_cent_CAR{datetime}.csv` | CT geographic centroids |
| `ct_wtcent_CAR{datetime}.csv` | CT pop-weighted centroids |
| `parcel_CAR{datetime}.csv` | Individual household parcels |

Column format: `row.names, id, opportunity, percentile, cutoff, accessibility`

### Known Issues
- Origins **must** have `id`, `lon`, `lat` columns in CRS EPSG:4326 (`proj_coord_crs`) before passing to `compute_accessibility()`.
- If the run is interrupted, resume by subsetting origins to `origins[last_idx:nrow(origins), ]` before calling `compute_accessibility()` again — results will be appended to the same file.
- `file_id` parameter allows splitting a run across multiple machines; `get_and_merge_files()` in Step D merges all matching files.
- Cutoffs are drive-time thresholds in minutes: default `c(5, 10, 15, 20, 25, 30, 35, 40, 45)`.
- Departure time is hardcoded to `"2025-03-21 18:00:00"` (Friday evening peak).

---

## Step D — Aggregate & Derive Pipeline Outputs

**File:** `2_summarize_measures.R`

**This is a pipeline-only script.** It reads raw accessibility outputs and produces clean, merged datasets for analysis. It does not compute any error or bias metrics.

### Functions & Sequence

**Phase 1 — Load spatial context:**
- `get_census_tracts()`, `get_lac_households(processed_path, proj_coord_crs)`, `get_city_boundary()`
- Filter to LA City: `la_city_ct` (CTs intersecting city boundary), `la_city_hh` (households in city CTs)
- Load `la_ct_key` from `processed_path/LAC_origins/la_ct_key.csv`

**Phase 2 — Read raw chunked output + derive relative measures:**
- `get_and_merge_files(density_path, pattern)` — lists all CSVs matching `pattern`, reads with `fread`, binds rows, removes NA id rows (header rows from appended files), returns data.table.
- `calc_relative_measures(data)` — appends four derived opportunity rows to the long output:

| Column | Definition |
|--------|-----------|
| `AFS` | `CNV + GRC + SMK + SPF` (all food stores) |
| `ARR` | `FF + RR` (all restaurants) |
| `RELSMK` | `SMK / AFS` — supermarket share of food store access |
| `RELRR` | `RR / ARR` — restaurant share of all restaurant access |

**Phase 3 — Aggregate + pivot wide:**
- `process_times(dt_household, la_city_hh, GEOID="GEOID_20", agg=TRUE)` → `dt_household_ct`
  - When `agg=TRUE`: groups by GEOID, computes per-measure mean, median, SD. **CV is not computed here — derived in Step E.**
  - Column name pattern after aggregation: `{type}_{opportunity}_{cutoff}_{scale}_{stat}` (e.g., `driving_SMK_15_parcel_mean`)
- `process_times(dt_ct_cent, la_ct_key, agg=FALSE)` → `dt_ct_centm` (wide format, one row per CT)
- `process_times(dt_ct_wtcent, la_ct_key, agg=FALSE)` → `dt_ct_wtcentm`

**Phase 4 — Merge + enrich:**
- Join `dt_ct_centm`, `dt_ct_wtcentm`, `dt_household_ct` by GEOID.
- Load USDA Food Atlas: `openxlsx::read.xlsx(..., sheet=3)` → join `usdafa_la` for GEOID comparison.
- `pivot_longer` + `separate_wider_delim` → long format `ct_driving` with columns `network, type, drive, pop_rep`.

**Phase 5 — Write outputs:**

### Inputs
- Chunked CSVs from Step C at `access_path/density/la_city/CATG/`
- `processed_path/LAC_origins/la_ct_key.csv`
- `base_path/USDA_foodatlas/FoodAccessResearchAtlasData2019.xlsx`

### Outputs
All written to `processed_path/LAC_cleaned/`:

| File | Contents |
|------|----------|
| `ct_driving_times.csv` | All CT-level measures (ct_cent, ct_wtcent, parcel-agg) in long format joined with USDA data |
| `dt_household_ct.csv` | Parcel→CT aggregated measures: mean/median/SD per CT, unweighted + pop-weighted. No CV. |
| `parcel_drivingdt.csv` | Individual household measures, long format |
| `parcel_driving_all.csv` | Parcel-level data joined with CT-level context |

### Known Issues
- CT `06037980022` (population = 0) was mis-geocoded; hardcoded replacement with `06037106645` applied in `parcel_driving1` via `mutate(GEOID=ifelse(...))`.
- `get_and_merge_files()` merges **all** CSVs matching the pattern — if a partial re-run produced an extra file, it will be double-counted. Clean up `access_path/density/la_city/CATG/` before re-running.
- `tidytable` is loaded in this script (in addition to `tidyverse`) for `separate_wider_delim` on large data.tables.

---

## Step E — Error & Bias Analysis

**File:** `3_prelim_results.Rmd` (standalone — can be knitted independently)

**This is the analysis entry point.** All validation metrics live here. The pipeline vs. analysis boundary is: everything in Steps A–D produces data; everything in Step E consumes it.

### Functions & Sequence

**Setup:**
1. Load `parcel_driving_all.csv` → `parcel_data_all`; join with `la_city_hh` geometry.
2. Load `ct_driving_times.csv` → `ct_drive_data`; merge with `la_ct` geometry.
3. Load `dt_household_ct.csv` → `parcel_data_ct`; merge with `la_ct` geometry.

**CV derivation** (first analysis step):
```r
for (col in grep("_parcel_sd$",   names(parcel_data_ct), value=TRUE))
  parcel_data_ct[[sub("_sd$",   "_cv",   col)]] <- parcel_data_ct[[col]] / parcel_data_ct[[sub("_sd$",   "_mean",   col)]] * 100
for (col in grep("_parcel_w_sd$", names(parcel_data_ct), value=TRUE))
  parcel_data_ct[[sub("_w_sd$", "_w_cv", col)]] <- parcel_data_ct[[col]] / parcel_data_ct[[sub("_w_sd$", "_w_mean", col)]] * 100
```

**Three origin representations compared** (parcel = ground truth):

| Label | Description |
|-------|-------------|
| `parcel_mean` | Mean household accessibility per CT — ground truth |
| `ct_cent` | CT geographic centroid measure |
| `ct_wtcent` | CT population-weighted centroid measure |

All metrics stratified by retailer type (`CNV`, `FF`, `GRC`, `RR`, `SMK`, `SPF`) and drive-time cutoff.

**Metrics computed:**

| Metric | Function/Package | Output |
|--------|-----------------|--------|
| Bias, MAE, RMSE | `Metrics::bias/mae/rmse()` | `tables_figures/table3.csv` |
| Paired t-test | `t.test(..., paired=TRUE)` | Inline table |
| Paired Wilcoxon | `wilcox.test(..., paired=TRUE)` | Inline table |
| Bland-Altman | `blandr::blandr.statistics()` | Faceted plots |
| CV map | Derived columns + `tmap` | Inline maps |
| Demographics by CV quartile | `tidycensus::get_acs()` + Kruskal-Wallis | `tables_figures/table4_{type}_{drive}.csv` |

**Bland-Altman details:** for each centroid type × retailer × drive-time group, computes bias (mean diff), 95% LoA (bias ± 1.96 SD), CIs using SE(bias)=s/√n and SE(LoA)=√3·s/√n with t_{n−1} df (Bland & Altman 1999). Proportional bias is tested by regressing `diff ~ mean`; significant slope (β) indicates discrepancy grows with accessibility magnitude.

Both t-test and Wilcoxon are run because count distributions are non-normal; Wilcoxon is the primary test.

### Inputs
- `processed_path/LAC_cleaned/parcel_driving_all.csv`
- `processed_path/LAC_cleaned/ct_driving_times.csv`
- `processed_path/LAC_cleaned/dt_household_ct.csv`
- ACS data via `tidycensus::get_acs()` (internet + Census API key required)

### Outputs
| File | Location |
|------|----------|
| `table3.csv` | `tables_figures/` |
| `table4_{type}_{drive}.csv` | `tables_figures/` |

### Known Issues
- CT `06037980022` → `06037106645` workaround applied again at parcel level.
- `tidycensus` requires a Census API key set via `census_api_key()` or `CENSUS_API_KEY` env var.
- Some CTs have missing CV values (noted for CT `06037300301`) — appear as NA in maps and are excluded from quartile analysis.

---

## Exploratory & Validation Scripts

Not part of the main pipeline — run independently as needed:

| File | Purpose |
|------|---------|
| `1_food_categories.Rmd` | Inspect NAICS category distributions in cleaned POI data |
| `1_visualizations.Rmd` | Maps of input data: boundaries, food POIs, household points |
| `helper/geocoder.R` | Geocoding validation: re-geocode a sample of POIs via Google + ArcGIS APIs and compare against Data Axle coordinates. Requires `GOOGLE_API_KEY` env var. Functions: `run_geocoding()`, `summarize_geocoding()`. |
| `helper/geo-duplicate-finder.R` | Identify likely duplicate POIs using Jaro-Winkler similarity + spatial proximity. Function: `find_geo_duplicates()`. |

---

## Benchmarks

Run from the repo root:
```r
source("benchmarks/run_all.R")
```
Set `RUN_ACCESSIBILITY <- FALSE` to skip `bench_accessibility.R` (hours for large origin/destination grids). Results written per-script to `benchmarks/results/`, then merged into `all_benchmarks_{timestamp}.csv`.

| Script | What it times |
|--------|--------------|
| `bench_cleaning.R` | Data cleaning pipeline |
| `bench_pipeline.R` | Full pipeline |
| `bench_accessibility.R` | `compute_accessibility()` over origin×destination size grids and cutoffs; `setup_r5()` timed separately |

---

## CRS Reference

| Variable | Value | Used for |
|----------|-------|---------|
| `proj_crs` | `26945` (NAD83 / California zone 5, feet) | Spatial joins, buffering, distance calculations |
| `proj_coord_crs` | `4326` (WGS 84) | r5r inputs/outputs, OSM data |
| `proj_buffer_size` | `5280 * 30` (30 miles in feet) | Study area buffer |

All r5r origin/destination inputs must be in `proj_coord_crs`. Spatial joins and distance calculations must be in `proj_crs`.
