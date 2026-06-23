
# =============================================================================
# STEP B: DATA CLEANING
# Cleans food environment POI dataset and prepares population representation
# origin points (census tract centroids, pop-weighted centroids).
#
# Food POI source is controlled by FOOD_POI_SOURCE in config.R:
#   "snap"       — SNAP retailer data (default; no FF/RR categories)
#   "data_axle"  — proprietary; file must be placed manually
#   file path    — user-supplied CSV or GeoPackage
#
# Parcel-level origins are skipped unless HOUSEHOLDS_PATH is set in config.R.
# =============================================================================

source("0_Libraries.R")
source("helper/geo-duplicate-finder.R")
# source("helper/geocoder.R") # in dev

# ------ BOUNDARIES ------
study_boundary <- get_study_boundary(STUDY_STATE, STUDY_COUNTY, STUDY_YEAR, proj_crs)
buffer         <- get_buffer_boundary(study_boundary)

# ------ CENSUS DATA ------
la_ct <- get_census_tracts(path = base_path, crs = proj_crs, state = STUDY_STATE,
                            year = STUDY_YEAR, county = STUDY_COUNTY)
la_cb <- get_census_blocks(path = base_path, crs = proj_crs, state = STUDY_STATE,
                            year = STUDY_YEAR, county = STUDY_COUNTY)

# ------ CENSUS TRACT CENTROIDS ------
# Run once when census data changes; uncomment to regenerate.
# calc_and_save_centroids(la_ct, la_cb, proj_crs, processed_path)

la_ct_wtcent_dat <- get_weight_centroids(processed_path, STUDY_STATE, STUDY_COUNTY)
la_ctcent_dat    <- get_centroids(processed_path, STUDY_STATE, STUDY_COUNTY)

# ------ FOOD POI CLEANING ------
# Dispatches to SNAP, Data Axle, or custom based on FOOD_POI_SOURCE in config.R.
save_and_clean_poi(year = STUDY_YEAR, state = STUDY_STATE,
                   processed_path = processed_path, boundary = buffer, source=FOOD_POI_SOURCE)

foodpoi <- get_foodpoi(year = STUDY_YEAR, path = processed_path) %>%
  sf::st_as_sf(coords = c("LONGITUDE", "LATITUDE"), crs = proj_coord_crs)

