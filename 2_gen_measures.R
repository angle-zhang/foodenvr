
# =============================================================================
# STEP C: GENERATING FOOD ENVIRONMENT MEASURES
# Computes network-based food accessibility (density) measures using r5r.
# compute_accessibility() wraps r5r::accessibility() with chunked processing.
#
# Runs for each combination of:
#   - Population representation: CT centroids, pop-weighted centroids,
#     household/parcel points (if HOUSEHOLDS_PATH is set in config.R)
#   - Food retail category: CNV, FF, GRC, RR, SMK, SPF, Not.included
#   - Drive-time cutoffs: 5–45 minutes
#
# Output: chunked CSVs appended to access_path, reassembled in 2_summarize_measures.R
# =============================================================================

source("0_Libraries.R")
source("./helper/gen-helper.R")

geoid_col  <- paste0("GEOID_", substr(proj_year, 3, 4))
study_area <- if (!is.null(STUDY_CITY)) gsub(" ", "_", STUDY_CITY) else gsub(" ", "_", proj_county)
output_path <- file.path(access_path, "density", study_area, "CATG", "")

# ------ LOAD CENSUS TRACTS ------
la_ct <- get_census_tracts(crs = proj_crs, state = proj_state,
                            year = proj_year, county = proj_county)

# ------ STUDY AREA FILTER ------
study_boundary <- get_city_boundary(crs = proj_coord_crs)

la_study_ct <- la_ct %>%
  dplyr::filter(lengths(sf::st_intersects(., sf::st_transform(study_boundary, proj_crs))) > 0) %>%
  sf::st_transform(proj_coord_crs)

# ------ CT CENTROIDS ------
la_ctcent_dat <- get_centroids(processed_path, proj_state, proj_county) %>%
  sf::st_transform(proj_coord_crs) %>%
  dplyr::mutate(id  = dplyr::row_number(),
                lon = sf::st_coordinates(.)[, 1],
                lat = sf::st_coordinates(.)[, 2])

# id <-> GEOID key for centroid methods
la_ct_key <- la_ctcent_dat %>%
  dplyr::select(id, GEOID) %>%
  sf::st_drop_geometry()

write.csv(la_ct_key, paste0(origins_path, "ct_key.csv"), row.names = FALSE)

# ------ POP-WEIGHTED CENTROIDS ------
la_ct_wtcent_dat <- get_weight_centroids(processed_path, proj_state, proj_county) %>%
  sf::st_transform(proj_coord_crs) %>%
  dplyr::merge(la_ct_key, by = "GEOID") %>%
  dplyr::mutate(lon = sf::st_coordinates(.)[, 1],
                lat = sf::st_coordinates(.)[, 2])

# ------ PARCEL / ADDRESS POINTS (optional) ------
if (!is.null(HOUSEHOLDS_PATH)) {
  la_hh <- load_address_points(HOUSEHOLDS_PATH, la_ct, proj_crs)

  la_study_hh <- la_hh %>%
    dplyr::filter(.data[[geoid_col]] %in% la_study_ct$GEOID) %>%
    sf::st_transform(proj_coord_crs)
}

# ------ ACCESSIBILITY COMPUTATION ------
poi_cols <- c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")

# CT geographic centroids
access_CAR <- compute_accessibility(
  origins     = la_ctcent_dat,
  destinations = foodpoi,
  mode        = "CAR",
  chunk_size  = CHUNK_SIZE_CAR,
  output_path = output_path,
  origin_type = "ct_cent_CAR",
  colnames    = poi_cols
)

# CT pop-weighted centroids
access_CAR <- compute_accessibility(
  origins     = la_ct_wtcent_dat,
  destinations = foodpoi,
  mode        = "CAR",
  chunk_size  = CHUNK_SIZE_CAR,
  output_path = output_path,
  origin_type = "ct_wtcent_CAR",
  colnames    = poi_cols
)

# Household parcels (only if HOUSEHOLDS_PATH is set)
if (!is.null(HOUSEHOLDS_PATH)) {
  access_CAR <- compute_accessibility(
    origins     = la_study_hh,
    destinations = foodpoi,
    mode        = "CAR",
    chunk_size  = CHUNK_SIZE_CAR,
    output_path = output_path,
    origin_type = "parcel",
    colnames    = poi_cols
  )
}
