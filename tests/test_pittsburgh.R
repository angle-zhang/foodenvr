
# Pittsburgh test script — run each section independently, flag errors
# Tests all non-r5r steps (accessibility computation requires Java 21 + OSM data)

STUDY_STATE  <- "PA"
STUDY_COUNTY <- "Allegheny"
STUDY_CITY   <- "Pittsburgh"
STUDY_YEAR   <- 2020
BUFFER       <- NULL
FOOD_POI_SOURCE <- "snap"
HOUSEHOLDS_PATH <- NULL
OSM_LOCATION <- NULL
JAVA_MEM        <- "12G"
CHUNK_SIZE_CAR  <- 4
CHUNK_SIZE_WALK <- 1000

cat("=== CONFIG OK ===\n")

# ── packages ──────────────────────────────────────────────────────────────────
cat("\n=== LOADING PACKAGES ===\n")
pkgs <- c("tidyverse","sf","tigris","crsuggest","osmextract","data.table",
          "arcgislayers","centr","CDCPLACES","tmap","tidycensus","broom")
for (p in pkgs) {
  ok <- requireNamespace(p, quietly=TRUE)
  cat(sprintf("  %-20s %s\n", p, if(ok) "OK" else "MISSING"))
}

# ── helper sources ────────────────────────────────────────────────────────────
cat("\n=== SOURCING HELPERS ===\n")
suppressMessages({
  library(tidyverse); library(sf); library(tigris); library(crsuggest)
  library(data.table); library(centr)
})
options(tigris_use_cache = TRUE)

tryCatch(source("helper/data_functions.R"),  error=function(e) cat("data_functions.R:", conditionMessage(e), "\n"))
tryCatch(source("helper/get-food-data.R"),   error=function(e) cat("get-food-data.R:", conditionMessage(e), "\n"))
tryCatch(source("helper/get-admin-data.R"),  error=function(e) cat("get-admin-data.R:", conditionMessage(e), "\n"))
tryCatch({
  source("helper/universal_variables.R")
  cat(sprintf("  proj_crs        = %d\n", proj_crs))
  cat(sprintf("  proj_buffer_size= %.1f\n", proj_buffer_size))
}, error=function(e) cat("universal_variables.R:", conditionMessage(e), "\n"))

# ── Step A: boundaries ────────────────────────────────────────────────────────
cat("\n=== STEP A: BOUNDARIES ===\n")

tryCatch({
  study_boundary <- get_study_boundary("PA", "Allegheny", proj_crs)
  cat("  get_study_boundary: OK —", nrow(study_boundary), "feature(s)\n")
}, error=function(e) cat("  get_study_boundary FAILED:", conditionMessage(e), "\n"))

tryCatch({
  city_boundary <- get_city_boundary(proj_crs, "PA", 2020, "Pittsburgh", "Allegheny")
  cat("  get_city_boundary: OK —", nrow(city_boundary), "feature(s)\n")
}, error=function(e) cat("  get_city_boundary FAILED:", conditionMessage(e), "\n"))

tryCatch({
  buf <- get_buffer_boundary(study_boundary, NULL, "PA", "Allegheny", "Pittsburgh", proj_crs)
  cat("  get_buffer_boundary (NULL/county): OK\n")
}, error=function(e) cat("  get_buffer_boundary FAILED:", conditionMessage(e), "\n"))

# ── Step A: census downloads ──────────────────────────────────────────────────
cat("\n=== STEP A: CENSUS DOWNLOADS ===\n")

base_path      <- "../0_shared-data/food-environment-measures/raw/"
processed_path <- "../0_shared-data/food-environment-measures/processed/"
if (!dir.exists(base_path)) dir.create(base_path, recursive=TRUE)

tryCatch({
  download_census_tracts("../0_shared-data/food-environment-measures/raw/", "PA", "Allegheny", 2020, land=TRUE)
  cat("  download_census_tracts: OK\n")
}, error=function(e) cat("  download_census_tracts FAILED:", conditionMessage(e), "\n"))

tryCatch({
  download_census_blocks("../0_shared-data/food-environment-measures/raw/", "PA", 2020, "Allegheny", land=TRUE)
  cat("  download_census_blocks: OK\n")
}, error=function(e) cat("  download_census_blocks FAILED:", conditionMessage(e), "\n"))

tryCatch({
  la_ct <- get_census_tracts("../0_shared-data/food-environment-measures/raw/", proj_crs, "PA", 2020, "Allegheny")
  cat("  get_census_tracts: OK —", nrow(la_ct), "tracts\n")
}, error=function(e) cat("  get_census_tracts FAILED:", conditionMessage(e), "\n"))

tryCatch({
  la_cb <- get_census_blocks("../0_shared-data/food-environment-measures/raw/", proj_crs, "PA", 2020, "Allegheny")
  cat("  get_census_blocks: OK —", nrow(la_cb), "blocks\n")
}, error=function(e) cat("  get_census_blocks FAILED:", conditionMessage(e), "\n"))

# ── Step B2: centroids ────────────────────────────────────────────────────────
cat("\n=== STEP B2: CENTROIDS ===\n")

tryCatch({
  calc_and_save_centroids(la_ct, la_cb, proj_crs, processed_path,
                          state="PA", county="Allegheny", year=2020)
  cat("  calc_and_save_centroids: OK\n")
}, error=function(e) cat("  calc_and_save_centroids FAILED:", conditionMessage(e), "\n"))

tryCatch({
  cents <- get_centroids(processed_path, "PA", "Allegheny")
  cat("  get_centroids: OK —", nrow(cents), "rows\n")
}, error=function(e) cat("  get_centroids FAILED:", conditionMessage(e), "\n"))

tryCatch({
  wcents <- get_weight_centroids(processed_path, "PA", "Allegheny")
  cat("  get_weight_centroids: OK —", nrow(wcents), "rows\n")
}, error=function(e) cat("  get_weight_centroids FAILED:", conditionMessage(e), "\n"))

# ── Step B1: SNAP POI ─────────────────────────────────────────────────────────
cat("\n=== STEP B1: SNAP POI ===\n")

source("helper/geo-duplicate-finder.R")
buf_4326 <- sf::st_transform(buf, 4326)

tryCatch({
  snap <- get_snap_current(polygon = buf_4326, proj_crs = 4326)
  cat("  get_snap_current: OK —", nrow(snap), "retailers\n")
  cat("  columns:", paste(names(snap)[1:min(8,ncol(snap))], collapse=", "), "\n")
}, error=function(e) cat("  get_snap_current FAILED:", conditionMessage(e), "\n"))

tryCatch({
  save_and_clean_snap_poi(year=2020, boundary=buf, processed_path=processed_path)
  cat("  save_and_clean_snap_poi: OK\n")
}, error=function(e) cat("  save_and_clean_snap_poi FAILED:", conditionMessage(e), "\n"))

cat("\n=== DONE ===\n")
cat("NOTE: OSM download, DEM, r5r accessibility (Steps A-network and C) not tested — require Java 21 and large data downloads.\n")
