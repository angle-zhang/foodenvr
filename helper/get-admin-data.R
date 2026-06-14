
# helper/get-admin-data.R
# Generic administrative boundary, census, and origin-point functions.
# All location parameters default to config.R values (proj_state, proj_county, etc.).

library(tigris)
library(arcgislayers)
library(sf)

# ── ArcGIS helper ─────────────────────────────────────────────────────────────

get_from_url <- function(url) {
  layer    <- arc_open(url)
  boundary <- arc_select(layer)
  if (any(!st_is_valid(boundary))) boundary <- st_make_valid(boundary)
  boundary
}

# ── Study and buffer boundaries ───────────────────────────────────────────────

# Returns the study county (or union of counties) as an sf polygon.
# Throws an error if the county name is not found — no silent fallback.
get_study_boundary <- function(state = proj_state, county = proj_county, crs = proj_crs) {
  all_counties <- tigris::counties(state = state, class = "sf")
  result <- all_counties %>% dplyr::filter(NAME %in% county)

  if (nrow(result) == 0) {
    stop(
      "County '", paste(county, collapse = "', '"), "' not found in state '", state, "'. ",
      "Run tigris::counties(state = '", state, "') to see valid county names."
    )
  }

  result %>% sf::st_union() %>% sf::st_as_sf() %>% sf::st_transform(crs)
}

# Returns the study city boundary via tigris::places().
# If STUDY_CITY is NULL, returns the county boundary instead.
# Throws an error if the city name is not found.
get_city_boundary <- function(crs = proj_crs, state = proj_state,
                               year = proj_year, city = STUDY_CITY,
                               county = proj_county) {
  if (is.null(city)) {
    return(get_study_boundary(state = state, county = county, crs = crs))
  }

  places <- tigris::places(state = state, class = "sf", year = year) %>%
    dplyr::filter(NAME == city)

  if (nrow(places) == 0) {
    stop(
      "City '", city, "' not found in state '", state, "'. ",
      "Run tigris::places(state = '", state, "') to see valid place names."
    )
  }

  places %>% sf::st_transform(crs)
}

# Returns the buffer polygon used as the r5r network extent.
# Dispatches on the type of BUFFER from config.R:
#   NULL    — county boundary (city study) or county + adjacent counties (county study)
#   numeric — fixed ring of that many miles around study_boundary
#   string  — reads a user-supplied sf-readable file
get_buffer_boundary <- function(study_boundary,
                                 buffer_val  = BUFFER,
                                 state       = proj_state,
                                 county      = proj_county,
                                 study_city  = STUDY_CITY,
                                 crs         = proj_crs) {
  if (is.numeric(buffer_val)) {
    u            <- sf::st_crs(crs)$units
    miles_in_crs <- if (grepl("foot|feet|ft", u, ignore.case = TRUE)) buffer_val * 5280
                    else                                                buffer_val * 1609.34
    return(sf::st_buffer(sf::st_transform(study_boundary, crs), miles_in_crs))
  }

  if (is.character(buffer_val) && nchar(buffer_val) > 0) {
    if (!file.exists(buffer_val)) stop("BUFFER file not found: ", buffer_val)
    return(sf::st_read(buffer_val) %>% sf::st_transform(crs))
  }

  # NULL default
  all_counties <- tigris::counties(state = state, class = "sf")
  study_ct     <- all_counties %>% dplyr::filter(NAME %in% county)

  if (!is.null(study_city)) {
    # city-level study: use the county as buffer
    buf <- study_ct %>% sf::st_union() %>% sf::st_transform(crs)
  } else {
    # county-level study: use county + all adjacent counties
    adjacent <- all_counties[lengths(sf::st_touches(all_counties, sf::st_union(study_ct))) > 0, ]
    buf <- dplyr::bind_rows(study_ct, adjacent) %>% sf::st_union() %>% sf::st_transform(crs)
  }

  buf
}

# ── Census tract and block download/read ──────────────────────────────────────

download_census_tracts <- function(path = base_path, state = proj_state,
                                    county = proj_county, year = proj_year, land = TRUE) {
  all_tracts <- tigris::tracts(state = state, county = county, year = year, class = "sf")

  if (land) all_tracts <- all_tracts %>% dplyr::filter(ALAND > 0)

  geo_path <- paste0(path, "geo_", county, "/")
  if (!dir.exists(geo_path)) dir.create(geo_path, recursive = TRUE)

  sf::st_write(all_tracts, paste0(geo_path, state, "_", county, "_", year, "_census_tracts.gpkg"), append = FALSE)
}

get_census_tracts <- function(path = base_path, crs = proj_crs, state = proj_state,
                               year = proj_year, county = proj_county, boundary = NULL) {
  geo_path <- paste0(path, "geo_", county, "/")
  ct <- sf::st_read(paste0(geo_path, state, "_", county, "_", year, "_census_tracts.gpkg")) %>%
    sf::st_transform(crs)

  if (!is.null(boundary)) {
    ct <- ct %>%
      dplyr::filter(lengths(sf::st_within(., boundary)) > 0)
  }

  ct
}

download_census_blocks <- function(path = base_path, state = proj_state,
                                    year = proj_year, county = proj_county, land = TRUE) {
  all_blocks <- tigris::blocks(state = state, county = county, year = year, class = "sf")

  if (land) {
    aland_col  <- paste0("ALAND", substr(year, 3, 4))
    all_blocks <- all_blocks %>% dplyr::filter(.data[[aland_col]] > 0)
  }

  geo_path <- paste0(path, "geo_", county, "/")
  if (!dir.exists(geo_path)) dir.create(geo_path, recursive = TRUE)

  sf::st_write(all_blocks, paste0(geo_path, state, "_", county, "_", year, "_census_blocks.gpkg"), append = FALSE)
}

get_census_blocks <- function(path = base_path, crs = proj_crs, state = proj_state,
                               year = proj_year, county = proj_county, boundary = NULL) {
  geo_path <- paste0(path, "geo_", county, "/")
  cb <- sf::st_read(paste0(geo_path, state, "_", county, "_", year, "_census_blocks.gpkg")) %>%
    sf::st_transform(crs)

  if (!is.null(boundary)) {
    cb <- cb %>% dplyr::filter(lengths(sf::st_within(., boundary)) > 0)
  }

  cb
}

# ── Census tract centroids ────────────────────────────────────────────────────

# Run once when census data changes; writes both centroid files to origins_path.
calc_and_save_centroids <- function(la_ct, la_cb, crs = proj_crs,
                                     processed_path = processed_path,
                                     state = proj_state, county = proj_county,
                                     year = proj_year) {
  tractce_col  <- paste0("TRACTCE", substr(year, 3, 4))
  pop_col      <- paste0("POP",     substr(year, 3, 4))
  file_prefix  <- paste0(state, "_", gsub(" ", "_", county))
  out_path     <- paste0(processed_path, "origins/")

  if (!dir.exists(out_path)) dir.create(out_path, recursive = TRUE)

  # unweighted centroid
  la_ctcent_dat <- la_ct %>%
    sf::st_centroid() %>%
    sf::st_transform(crs)

  # population-weighted centroid from census block centroids
  la_ct_wtcent <- calc_pop_weighted_centroid(la_cb, tractce_col, pop_col) %>%
    sf::st_transform(crs)

  # join tract attributes onto weighted centroid geometry
  # (TRACTCE in tracts; tractce_col in blocks/weighted centroids)
  la_ct_wtcent_dat <- la_ct %>%
    sf::st_drop_geometry() %>%
    dplyr::left_join(la_ctcent %>% sf::st_drop_geometry(),
                     by = stats::setNames(tractce_col, "TRACTCE")) %>%
    sf::st_as_sf() %>%
    dplyr::filter(!sf::st_is_empty(.))

  sf::write_sf(la_ct_wtcent_dat, paste0(out_path, file_prefix, "_ct_wtcent.gpkg"))
  sf::write_sf(la_ctcent_dat,    paste0(out_path, file_prefix, "_ctcent.gpkg"))
}

get_centroids <- function(path = processed_path, state = proj_state, county = proj_county) {
  file_prefix <- paste0(state, "_", gsub(" ", "_", county))
  sf::st_read(paste0(path, "origins/", file_prefix, "_ctcent.gpkg"))
}

get_weight_centroids <- function(path = processed_path, state = proj_state, county = proj_county) {
  file_prefix <- paste0(state, "_", gsub(" ", "_", county))
  sf::st_read(paste0(path, "origins/", file_prefix, "_ct_wtcent.gpkg"))
}

# ── User-supplied address / parcel points ─────────────────────────────────────

# Reads any sf-readable point file and standardises it for the pipeline.
# Adds a sequential id column. If GEOID_{year} is absent, assigns it via
# spatial join against la_ct (slow for large files — pre-join if possible).
load_address_points <- function(path, la_ct, crs = proj_crs, year = proj_year) {
  if (!file.exists(path)) stop("HOUSEHOLDS_PATH file not found: ", path)

  pts       <- sf::st_read(path) %>% sf::st_transform(crs) %>% dplyr::mutate(id = dplyr::row_number())
  geoid_col <- paste0("GEOID_", substr(year, 3, 4))

  if (!geoid_col %in% names(pts)) {
    message("No '", geoid_col, "' column found — assigning via spatial join with census tracts.")
    pts <- sf::st_join(pts, la_ct %>% dplyr::select(GEOID) %>% sf::st_transform(crs)) %>%
      dplyr::rename(!!geoid_col := GEOID)
  }

  pts
}

# ── Elevation and street network download ─────────────────────────────────────

download_dem <- function(path = base_path, boundary, county = proj_county) {
  require(elevatr)
  require(terra)

  geo_path <- paste0(path, "geo_", county, "/")
  if (!dir.exists(geo_path)) dir.create(geo_path, recursive = TRUE)

  dem <- elevatr::get_elev_raster(boundary, z = 10)
  terra::writeRaster(dem, paste0(geo_path, county, "_dem.tif"), overwrite = TRUE)
}

# Downloads the OSM street network for the given bounding box.
# Uses OSM_LOCATION from config.R if set; otherwise auto-detects via oe_match().
download_osm <- function(county = proj_county, bbox, location = OSM_LOCATION) {
  require(osmextract)

  geo_path <- paste0(base_path, "geo_", county, "/")
  if (!dir.exists(geo_path)) dir.create(geo_path, recursive = TRUE)

  target <- if (!is.null(location)) location else sf::st_as_sfc(bbox)
  oe_get(target, download_directory = geo_path, download_only = TRUE)
}

# ── LA County-specific utilities (not used in generic pipeline) ───────────────
# These functions target LA County ArcGIS services and are retained for
# compatibility with existing LA-specific exploratory scripts.

get_spa_boundaries <- function() {
  get_from_url("https://services.arcgis.com/RmCCgQtiZLDCtblq/arcgis/rest/services/Service_Planning_Areas_2022_view/FeatureServer/4/query?outFields=*&where=1%3D1")
}

get_openspace_parks <- function() {
  get_from_url("https://services1.arcgis.com/X1hcdGx5Fxqn4d0j/ArcGIS/rest/services/Land_Use_and_Zoning/FeatureServer/1")
}

get_zoning <- function() {
  get_from_url("https://services1.arcgis.com/X1hcdGx5Fxqn4d0j/ArcGIS/rest/services/Land_Use_and_Zoning/FeatureServer/3")
}
