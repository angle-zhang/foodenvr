# Foodenvr. Food Environment Accessibility Measures

An open-source R workflow for computing food environment 
accessibility measures based on drive times at the household and census tract level, and 
evaluating how population representation method (census tract centroid, 
population-weighted centroid, household parcel point) affects measured 
access to food retailers. The current workflow is for the city of Los Angeles but this workflow is configurable for any U.S. city or county.

---

## Prerequisites

- **R** 4.4.0
- **Java 21** (required by `r5r`; see [rJavaEnv](https://github.com/e-kotov/rJavaEnv) 
  for installation)
- **RAM**: ≥ 16 GB recommended for driving-time computation; 
  16 GB+ for parcel-level runs
- R packages: installed automatically via `0_Libraries.R`, but key dependencies 
  are `r5r`, `sf`, `tigris`, `data.table`, `tidyverse` 

---

## Quick Start (LA County)

**`config.R`** — edit these values before running anything else:
- base_path: where you are storing your raw data
- processed_path: where you are storing intermediate data and outputs 
- **Java memory guidance**: set this to roughly 75% of available RAM. 
Running at 12G requires ~16G total; reduce to 6G for 8G machines and 
decrease `CHUNK_SIZE_CAR` in `config.R` to compensate.

```r
# Step 1 — Download raw data
source("1_data_collection.R")

# Step 2 — Clean food POI and assign categories
source("1_data_cleaning.R")

# Step 3 — Compute accessibility measures (~hours; requires Java + OSM network)
source("2_gen_measures.R")

# Step 4 — Aggregate and merge measures
source("2_summarize_measures.R")

# Step 5 — Compare methods and generate results
rmarkdown::render("3_prelim_results.Rmd")
```

Each script begins with `source("0_Libraries.R")`, which loads packages, sets paths, and sources all helpers.

**Java memory guidance**: set this to roughly 75% of available RAM. 
Running at 12G requires ~16G total; reduce to 6G for 8G machines and 
increase `CHUNK_SIZE_CAR` in `config.R` to compensate.

---

## Adapting to a New City or County

All location-specific parameters live in **`config.R`** - edit these values before running anything else:

```r
STUDY_STATE   <- "CA"
STUDY_COUNTY  <- "Los Angeles"
STUDY_CITY    <- "Los Angeles"    # must match tigris::places() NAME field
STUDY_YEAR    <- 2020
OSM_LOCATION  <- "socal"          # geofabrik slug; run osmextract::oe_match()
                                  # to find the right value for your region
```

Everything else is derived from these values automatically. To see derived variables, go to `helper/universal_variables.R`

### Data you must supply yourself

Two constructs do not have complete public data and either must be provided manually or downloaded from incomplete public databases:

| Input | LA County source | Alternatives for other regions |
|-------|-----------------|-------------------------------|
| **Residential parcel points** | LA County Tax Assessor GDB | County assessor data; [OpenAddresses](https://openaddresses.io/); Census LODES/WAC | 
| **Food POI** | Data Axle (proprietary) | SNAP retailer data (public; downloaded automatically if you set `FOOD_POI_SOURCE = "snap"` in `config.R` |

Set `HOUSEHOLDS_PATH` in `config.R` to point to your parcel file. It 
must be a point layer with columns: `id` (integer), `GEOID_<year>` 
(character), `UseType`, `EXCLUDE`. If parcel data is unavailable, you 
can skip the parcel-level computation and run only the census tract 
centroid and population-weighted centroid methods.

---

## Data sources

| Data | Source | Access | Script |
|------|--------|--------|--------|
| Census tracts + blocks | Census TIGER/Line via `tigris` | Public | `1_data_collection.R` |
| Street network (OSM) | Geofabrik via `osmextract` | Public | `1_data_collection.R` |
| SNAP retailer locations | USDA via ArcGIS REST | Public | `1_data_collection.R` |
| CDC PLACES health outcomes | CDC via `CDCPLACES` package | Public | `1_data_collection.R` |
| Food POI (primary) | Data Axle | **Proprietary** | `1_data_cleaning.R` |
| Residential parcels | County assessor | **Must supply** | `2_gen_measures.R` |
| NAICS category mapping | [Google Sheet](https://docs.google.com/spreadsheets/d/1y7TxLRUXCcgd-T4_mGAXaAwAR7R00JxJDjJ9IhAucAA) | Public | `1_data_cleaning.R` |

---

## Pipeline

| Script | Section | Description |
|--------|---------|-------------|
| `0_Libraries.R` | — | Load packages, set paths, source helpers |
| `1_data_collection.R` | A | Download census, OSM, SNAP, and health data |
| `1_data_cleaning.R` | B | Clean Data Axle POI; assign food categories via NAICS |
| `2_gen_measures.R` | C | Compute drive-time accessibility with `r5r` (chunked) |
| `2_summarize_measures.R` | D | Merge chunks; aggregate parcels to census tract level |
| `3_prelim_results.Rmd` | E | Compare methods; produce tables and maps |

### Food retailer categories

POIs are classified into seven categories mapped via NAICS codes:

| Code | Category |
|------|----------|
| `CNV` | Convenience store |
| `FF` | Fast food |
| `GRC` | Grocery |
| `RR` | Restaurant |
| `SMK` | Supermarket |
| `SPF` | Specialty food |
| `Not.included` | Excluded retailers |

Note: SNAP retailer data do not have restaurants or fast food restaurants as a category since most states do not authorize them as SNAP-eligible food retailers (with a few exceptions).

### Population representation methods

Measures are produced for three origin point types:
- **`ct_cent`** — unweighted census tract centroids
- **`ct_wtcent`** — population-weighted centroids (using 2020 census block counts)
- **`parcel`** — individual residential parcels (household-level ground truth)

Drive-time cutoffs can be specified by the user but generally are at 5, 10, 15 minute drive time increments. Walkability may also be calculated by setting `mode="WALK"` in the function call `compute_accessibility` from the file `2_gen_measures.R`

---

## Outputs

Final outputs are written to `processed_path/LAC_cleaned/`:

| File | Contents |
|------|----------|
| `ct_driving_times.csv` | All three methods merged at census tract level |
| `parcel_drivingdt.csv` | Household-level measures (long format) |
| `parcel_driving_all.csv` | Household measures merged with census tract data |
| `dt_household_ct.csv` | Parcel measures aggregated to census tract (mean, median, SD, CV) |

Column naming convention: `{network}_{category}_{cutoff}_{method}` 
(e.g., `driving_SMK_15_ct_wtcent`).

---

## Citation

If you use this pipeline, please cite:

> Zhang AW, Cai Y, Macdonald B, Shah P, Espinoza J, Wilson J (Under review). 
> Foodenvr: Quantifying error and bias in food environment measures using an open source workflow.

---

## License

Foodenvr is open source and licensed under the MIT License. OpenStreetMap's [Open Database License](https://www.openstreetmap.org/copyright/) requires that derivative works provide proper attribution. 
