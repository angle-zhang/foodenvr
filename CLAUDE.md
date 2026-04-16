# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## RULES 
**YOU MUST FOLLOW THESE RULES THEY ARE NON-NEGOTIABLE**
1. WRITE SIMPLE, HUMAN-READABLE CODE WHEN POSSIBLE, AVOIDING COMPLEX PROCEDURES WHEN SIMPLE ONES MAY BE POSSIBLE WITH JUST A FEW MORE LINES OF CODE

2. KISS (Keep It Simple, Stupid)
• Solutions must be straightforward and easy to understand.
• Avoid over-engineering or unnecessary abstraction.
• Prioritise code readability and maintainability.

3. YAGNI (You Aren’t Gonna Need It)
• Do not add speculative features or future-proofing unless explicitly required.
• Focus only on immediate requirements and deliverables.
• Minimise code bloat and long-term technical debt.

4. Principles

Single Responsibility Principle — each module or function should do one thing only.

Open-Closed Principle — software entities should be open for extension but closed for modification.

Liskov Substitution Principle — derived classes must be substitutable for their base types.

Interface Segregation Principle — prefer many specific interfaces over one general-purpose interface.

Dependency Inversion Principle — depend on abstractions, not concrete implementations.

## Project Overview

This is an R-based geospatial research project studying food environment access and Latino health outcomes in Los Angeles County. The project calculates network-based food accessibility measures (using `r5r` with OpenStreetMap road networks) for LA County households and census tracts, then links those measures to health outcome data from Latino health study participants.

## Running Scripts

Scripts are designed to be sourced from within the `R-food-access-lh/` directory (the working directory must be set here). All scripts begin with `source("0_Libraries.R")`.

Run a script in R:
```r
setwd("R-food-access-lh/")
source("1_data_collection.R")
```

Run the Rmd reports by knitting in RStudio or:
```r
rmarkdown::render("3_prelim_results.Rmd")
```

## Key Configuration

**Java memory** (`0_Libraries.R`): `r5r` requires Java 21 and significant RAM. The option `options(java.parameters = "-Xmx12G")` must be set before loading `r5r`. On SSI lab computers, `rJavaEnv` is used to install/set Java; on personal machines, `JAVA_HOME` must be set manually.

**Shared data paths** (`0_Libraries.R`):
- `base_path`: raw input data at `../0_shared-data/food-environment-measures/raw/`
- `processed_path`: cleaned/processed outputs at `../0_shared-data/food-environment-measures/processed/`
- `access_path`: accessibility results at `processed_path/LAC_accessibility`

These paths point to a shared data directory **outside** this repo and are not tracked by git.

## Pipeline Architecture

The scripts are numbered to indicate execution order:

| Script | Role |
|--------|------|
| `0_Libraries.R` | Load packages, set paths, source all helpers |
| `1_data_collection.R` | Download raw data (census tracts/blocks, OSM, DEM, SNAP, CDC PLACES) |
| `1_data_cleaning.R` | Clean Data Axle POI data and assign food categories via NAICS codes |
| `1_food_categories.Rmd` | Exploratory analysis of food POI categories |
| `2_gen_measures.R` | Compute network-based accessibility using `r5r::accessibility()` in chunks |
| `2_summarize_measures.R` | Merge chunked output files, aggregate to census tract level, write final CSVs |
| `2_health_data_cleaning.R` | Process geocoded participant data (El Sendero Latino Health study), compute accessibility for participant addresses |
| `3_prelim_results.Rmd` | Standalone analysis report; loads pre-computed measures and runs comparisons |

## Helper Functions

All helpers are sourced by `0_Libraries.R`:

- **`helper/get-la-county-admin-data.R`**: Getters/downloaders for spatial boundaries (county, city, SPAs, census tracts/blocks, households from parcel GDB, OSM network, centroids). Key functions: `get_city_boundary()`, `get_census_tracts()`, `get_lac_households()`, `get_lac_weight_centroids()`, `download_osm()`.

- **`helper/get-food-data.R`**: Getters/downloaders for food POI data sources (Data Axle, SNAP retailers via ArcGIS, LA County food inspection data). Key functions: `get_data_axle()`, `get_snap_current()`.

- **`helper/get-health-data.R`**: Wrapper around `CDCPLACES` package. Key function: `get_CDCPlaces()`.

- **`helper/gen-helper.R`**: Core compute functions. `compute_accessibility()` wraps `r5r::accessibility()` with chunked processing and file-append output (needed due to RAM limits). `get_and_merge_files()` reassembles chunked CSVs. `process_times()` reshapes long accessibility output to wide format and optionally aggregates parcels to census tract level. `calc_chunk_size()` estimates safe chunk sizes based on available RAM.

- **`helper/data_functions.R`**: Spatial geometry helpers: `calc_pop_weighted_centroid()`, `st_centroid_within_poly()`, `clipintersect_boundary()`.

## Food POI Categories

Food POIs are categorized using NAICS codes matched against a classification scheme from a Google Sheet (`naics` variable in `1_data_cleaning.R`). The resulting categories stored in `foodpoi.csv` columns are: `CNV` (convenience), `FF` (fast food), `GRC` (grocery), `RR` (restaurant), `SMK` (supermarket), `SPF` (specialty food), `Not.included`.

## Accessibility Output Format

`compute_accessibility()` appends results to CSVs named `{origin_type}_{mode}{datetime}.csv`. These chunked files are reassembled by `get_and_merge_files()` using the `origin_type` string as a pattern. Column names after reassembly: `row.names, id, opportunity, percentile, cutoff, accessibility`.

After `process_times()`, columns follow the pattern: `{type}_{opportunity}_{cutoff}_{scale}` (e.g., `driving_GRC_15_ct_wtcent`).

## CRS Handling

- `proj_crs` is set dynamically via `crsuggest::suggest_crs(get_county_boundary())` — a projected CRS appropriate for LA County
- OSM/r5r data requires CRS proj_coord_crs; spatial joins and `r5r` calls transform to/from proj_coord_crs as needed
- Households (`la_hh`) have `GEOID_20` stored as numeric (a known issue noted in TODOs)
