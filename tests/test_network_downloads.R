
# Pittsburgh DEM + OSM download test — run from repo root.
# Outputs are written to a temp subdir and deleted on exit.

STUDY_STATE  <- "PA"
STUDY_COUNTY <- "Allegheny"
STUDY_CITY   <- "Pittsburgh"
STUDY_YEAR   <- 2020
BUFFER       <- NULL
FOOD_POI_SOURCE <- "snap"
HOUSEHOLDS_PATH <- NULL
OSM_LOCATION <- NULL

suppressMessages({
  library(tidyverse); library(sf); library(tigris)
  library(crsuggest); library(data.table); library(centr)
})
options(tigris_use_cache = TRUE)

source("helper/data_functions.R")
source("helper/get-food-data.R")
source("helper/get-admin-data.R")
source("helper/universal_variables.R")

# Use a temp directory so outputs are isolated and easy to clean up
tmp_path <- file.path(tempdir(), "pittsburgh_test_network\\")
dir.create(tmp_path, recursive = TRUE, showWarnings = FALSE)
 print(tmp_path)
base_path <- tmp_path
on.exit({
  unlink(tmp_path, recursive = TRUE)
  cat("\n  [cleanup] temp outputs deleted:", tmp_path, "\n")
}, add = TRUE)

cat("=== STEP A: BOUNDARIES (for bbox) ===\n")
study_boundary <- get_study_boundary("PA", "Allegheny", proj_crs)
buf            <- get_buffer_boundary(as(file.path(tmp_path, "geo_Allegheny"), pattern = "\\.pbf$", full.names = TRUE)
  if (length(pbf) == 0) pbf <- list.files(file.path(tmp_path, "geo_Allegheny"), pattern = "\\.(pbf|gpkg)$", full.names = TRUE)
  if (length(pbf) == 0) stop("No .pbf/.gpkg file written")
  size_mb <- round(file.size(pbf[1]) / 1e6, 1)
  cat("  download_osm: OK —", elapsed, "s —", size_mb, "MB —", basename(pbf[1]), "\n")
  cat("  returned path:", result, "\n")
}, error = function(e) cat("  download_osm FAILED:", conditionMessage(e), "\n"))

cat("\n=== DONE ===\n")
