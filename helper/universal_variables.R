proj_coord_crs <- 4326

# fetch study county boundary in geographic CRS for CRS suggestion
study_boundary_geo <- tigris::counties(state = STUDY_STATE, year= STUDY_YEAR, class = "sf") %>%
  dplyr::filter(NAME %in% STUDY_COUNTY)

if (nrow(study_boundary_geo) == 0) {
  stop(
    "STUDY_COUNTY '", STUDY_COUNTY, "' not found in state '", STUDY_STATE, "'. ",
    "Run tigris::counties(state = '", STUDY_STATE, "') to see valid county names."
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