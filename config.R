# ── Paths ────────────────────────────────────────────────────────
base_path      <- "../0_shared-data/food-environment-measures/raw/"
processed_path <- "../0_shared-data/food-environment-measures/processed/"

# ── Study area ────────────────────────────────────────────────────────────────
# State abbreviation and county name exactly as in Census TIGER/Line.
# To verify valid names: tigris::counties(state = STUDY_STATE)
# An unrecognised name will throw an error — no silent fallback.
STUDY_STATE  <- "CA"
STUDY_COUNTY <- "Los Angeles"

# City name as it appears in tigris::places(state = STUDY_STATE).
# Set to NULL to run at county level (no city filter applied).
STUDY_CITY   <- "Los Angeles"

# Census year. Controls which TIGER/Line vintage is downloaded (2010 or 2020).
STUDY_YEAR   <- 2020

# ── Buffer (edge-effect mitigation) ──────────────────────────────────────────
# r5r loads the street network for this area; it must extend beyond the study
# boundary so access near the edge is not underestimated.
#
# NULL        — if study area is a city: uses the containing county boundary.
#               if study area is a county (STUDY_CITY = NULL): uses all counties
#               sharing a border, fetched automatically via tigris::counties().
# Numeric     — adds a fixed ring of that many miles around the study boundary.
# File path   — reads a user-supplied sf-readable polygon (any format st_read
#               supports) and uses it as-is.
BUFFER <- NULL

# ── Food POI ──────────────────────────────────────────────────────────────────
# "snap"      — default. Current SNAP retailer locations are fetched automatically
#               from the USDA ArcGIS REST API (no sign-in required). Historical
#               data can be downloaded with download_snap_historical(). FF and RR
#               category columns are zero: SNAP does not authorise restaurants.
# "data_axle" — proprietary dataset. File must be placed manually at:
#               processed_path/food_environment/{year}_data_axle_{state}.csv
# File path   — user-supplied CSV or GeoPackage. Must have LATITUDE/LONGITUDE
#               (or geometry) and binary columns for each food category.
FOOD_POI_SOURCE <- "snap"

# ── Address / parcel data ─────────────────────────────────────────────────────
# NULL        — skips parcel-level run. Only CT centroid and pop-weighted centroid
#               methods are computed.
# File path   — any sf-readable point file. Must have a numeric id column.
#               If GEOID_{year} is absent, tract GEOIDs are assigned automatically
#               via spatial join with the downloaded census tracts.
# HOUSEHOLDS_PATH <- NULL
HOUSEHOLDS_PATH <- paste(base_path, "NULL") # edit NULL to include your file path + name

# ── OSM network ───────────────────────────────────────────────────────────────
# NULL        — osmextract::oe_match() picks the best Geofabrik extract for the
#               buffer bounding box automatically.
# String      — override with a Geofabrik slug (e.g., "southern-california",
#               "new-york") if auto-selection downloads more than needed. 
                # Use code below to identify slug
                # library(osmextract)
                # 
                # # Search for a specific region (e.g., California)
                # california_slug <- geofabrik_zones[grep("California", geofabrik_zones$id), ]
                # print(california_slug)
OSM_LOCATION <- NULL

# ── Performance ───────────────────────────────────────────────────────────────
# function for calculating chunk size
calc_chunk_size <- function(ram, mode) { 
  # chunk size
  if (mode == "WALK") dt_chunk <- 100000 # WALK TIME CHUNK SIZE for 128 GB ram
  else if (mode == "CAR") dt_chunk <- 1000 # DRIVE TIME CHUNK SIZE  for 128 GB ram
  proportion <- ram/128
  chunk_size <- floor(dt_chunk * proportion)  
  return(chunk_size)
  
}

JAVA_MEM        <- "12G"   # ~75% of available RAM
CHUNK_SIZE_CAR  <- calc_chunk_size(12, "CAR")
CHUNK_SIZE_WALK <- calc_chunk_size(12, "WALK")

