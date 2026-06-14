
# =============================================================================
# STEP A: DATA COLLECTION
# Downloads all raw input data required for the food environment workflow:
#   - Spatial boundaries (census tracts, census blocks)
#   - Elevation data (DEM via elevatr)
#   - Street network (OSM via osmextract)
#   - Food POI: SNAP retailers (public, default) or Data Axle (proprietary)
#   - Health outcome data (CDC PLACES)
# Edit config.R before running this script.
# =============================================================================

source("0_Libraries.R")

# ------ BOUNDARIES ------
study_boundary <- get_study_boundary(proj_state, proj_county, proj_crs)
buffer         <- get_buffer_boundary(study_boundary)
buffer_4326    <- sf::st_transform(buffer, proj_coord_crs)
lac_bbox       <- sf::st_bbox(buffer_4326)

# ------ CENSUS TRACT AND BLOCK DATA ------
download_census_tracts(state = proj_state, county = proj_county, year = proj_year, land = TRUE)
download_census_blocks(state = proj_state, county = proj_county, year = proj_year, land = TRUE)

# ------ ELEVATION AND STREET NETWORK ------
download_dem(path = base_path, boundary = buffer, county = proj_county)
download_osm(county = proj_county, bbox = lac_bbox)

# ------ NAICS FOOD CATEGORY CLASSIFICATION ------
# Downloads NAICS → food-category mapping from a Google Sheet (requires googlesheets4 auth).
# Only needed when FOOD_POI_SOURCE = "data_axle".
# save_naics(processed_path)

# ------ SNAP FOOD POI (public, default) ------
# Current SNAP retailers are fetched in 1_data_cleaning.R via save_and_clean_poi().
# To download historical SNAP data (through 2022) run:
# download_snap_historical()

# ------ HEALTH OUTCOME DATA (CDC PLACES) ------
CDCPlaces_dict <- get_CDCPlaces_dict()
places_vars <- get_CDCPlaces(
  geography = "census",
  measure   = c("DIABETES", "OBESITY", "FOODSTAMP", "FOODINSECU", "HOUSINSECU"),
  state     = proj_state,
  geometry  = TRUE,
  release   = "2024"
) %>%
  dplyr::filter(countyname == proj_county)
