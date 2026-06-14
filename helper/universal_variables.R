
# helper/universal_variables.R
# Derives common variables from config.R (sourced before this file in 0_Libraries.R).
# CRS is auto-detected via crsuggest; buffer size is computed unit-aware.
# Do not set proj_crs or proj_buffer_size manually here — edit config.R instead.

proj_year   <- STUDY_YEAR
proj_state  <- STUDY_STATE
proj_county <- STUDY_COUNTY

proj_coord_crs <- 4326

# fetch study county boundary in geographic CRS for CRS suggestion
study_boundary_geo <- tigris::counties(state = proj_state, class = "sf") %>%
  dplyr::filter(NAME %in% proj_county)

if (nrow(study_boundary_geo) == 0) {
  stop(
    "STUDY_COUNTY '", proj_county, "' not found in state '", proj_state, "'. ",
    "Run tigris::counties(state = '", proj_state, "') to see valid county names."
  )
}

# suggest best projected CRS for this location
proj_crs <- as.integer(
  crsuggest::suggest_crs(study_boundary_geo, type = "projected")$crs_code[1]
)

# compute buffer size in CRS units (30-mile default)
proj_buffer_size <- {
  u <- sf::st_crs(proj_crs)$units
  if (is.null(u) || grepl("metre|meter", u, ignore.case = TRUE)) 30 * 1609.34
  else if (grepl("foot|feet|ft",         u, ignore.case = TRUE)) 30 * 5280
  else stop("Unrecognised CRS units '", u, "' — set proj_buffer_size manually in universal_variables.R.")
}
