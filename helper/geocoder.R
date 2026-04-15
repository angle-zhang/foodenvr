# TODO
# Find best approach: https://www.mdpi.com/2220-9964/13/6/170

# Geocode a single address via the Google Geocoding API.
# Returns a named vector c(lat, lon); NAs on failure.
geocode_google <- function(address, google_api_key) {
  resp <- tryCatch(
    httr::GET("https://maps.googleapis.com/maps/api/geocode/json",
              query = list(address = address, key = google_api_key)),
    error = function(e) NULL
  )
  if (is.null(resp) || httr::http_error(resp)) return(c(lat = NA_real_, lon = NA_real_))
  parsed <- httr::content(resp, as = "parsed")
  if (parsed$status != "OK" || length(parsed$results) == 0) return(c(lat = NA_real_, lon = NA_real_))
  loc <- parsed$results[[1]]$geometry$location
  c(lat = loc$lat, lon = loc$lng)
}

# Geocode a single address via the ArcGIS World Geocoder REST API (no key required).
# Returns a named vector c(lat, lon); NAs on failure.
geocode_arcgis <- function(address) {
  resp <- tryCatch(
    httr::GET("https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/findAddressCandidates",
              query = list(SingleLine = address, outFields = "*", f = "json", maxLocations = 1)),
    error = function(e) NULL
  )
  if (is.null(resp) || httr::http_error(resp)) return(c(lat = NA_real_, lon = NA_real_))
  parsed <- httr::content(resp, as = "parsed")
  if (is.null(parsed$candidates) || length(parsed$candidates) == 0) return(c(lat = NA_real_, lon = NA_real_))
  loc <- parsed$candidates[[1]]$location
  c(lat = loc$y, lon = loc$x)
}

# Compute pairwise distances (metres) between two sets of lon/lat points.
# Returns distances only for rows where all four coordinates are non-NA.
dist_between_coords <- function(lon1, lat1, lon2, lat2) {
  valid <- !is.na(lon1) & !is.na(lat1) & !is.na(lon2) & !is.na(lat2)
  if (sum(valid) == 0) return(numeric(0))
  orig <- st_as_sf(data.frame(lon = lon1[valid], lat = lat1[valid]), coords = c("lon", "lat"), crs = 4326) |> st_transform(proj_crs)
  regc <- st_as_sf(data.frame(lon = lon2[valid], lat = lat2[valid]), coords = c("lon", "lat"), crs = 4326) |> st_transform(proj_crs)
  as.numeric(st_distance(orig, regc, by_element = TRUE))
}

# --- Step 1: Geocode ---
# Sample n records from data, re-geocode each address via Google and ArcGIS,
# and return the sample with added geocoded coordinate columns.
#
# Arguments:
#   data           - foodpoi data frame (needs ADDRESS.LINE.1, CITY, ZIPCODE, LATITUDE, LONGITUDE)
#   google_api_key - Google Maps API key; NULL skips Google
#   n              - number of records to sample
#   seed           - random seed for reproducibility
#
# Returns the sampled data frame with extra columns:
#   address_str, google_lat, google_lon, arcgis_lat, arcgis_lon
run_geocoding <- function(data, google_api_key = NULL, n = 100, seed = 42) {
  require(httr)

  set.seed(seed)
  samp <- data[sample(nrow(data), min(n, nrow(data))), ] |>
    mutate(address_str = paste(ADDRESS.LINE.1, CITY, "CA", ZIPCODE))

  message(sprintf("Geocoding %d sampled addresses...", nrow(samp)))

  google_results <- if (!is.null(google_api_key)) {
    message("  Running Google Geocoding API...")
    lapply(samp$address_str, geocode_google, google_api_key = google_api_key)
  } else {
    message("  No Google API key supplied — skipping Google geocoding.")
    replicate(nrow(samp), c(lat = NA_real_, lon = NA_real_), simplify = FALSE)
  }

  message("  Running ArcGIS World Geocoder API...")
  arcgis_results <- lapply(samp$address_str, geocode_arcgis)

  samp$google_lat <- sapply(google_results, `[[`, "lat")
  samp$google_lon <- sapply(google_results, `[[`, "lon")
  samp$arcgis_lat <- sapply(arcgis_results, `[[`, "lat")
  samp$arcgis_lon <- sapply(arcgis_results, `[[`, "lon")

  message(sprintf(
    "  Google: %d/%d succeeded | ArcGIS: %d/%d succeeded",
    sum(!is.na(samp$google_lon)), nrow(samp),
    sum(!is.na(samp$arcgis_lon)), nrow(samp)
  ))

  samp
}

# --- Step 2: Summarize ---
# Compare re-geocoded coordinates (output of run_geocoding) against original Data Axle coords.
#
# Returns a list with:
#   $summary       - data frame: mean, median, SD, p95 distance in metres per source
#   $google_dist_m - numeric vector of per-record distances (metres) for Google
#   $arcgis_dist_m - numeric vector of per-record distances (metres) for ArcGIS
#   $tests         - list of wilcox.test results
summarize_geocoding <- function(samp) {
  require(sf)

  google_dist_m <- dist_between_coords(samp$LONGITUDE, samp$LATITUDE, samp$google_lon, samp$google_lat)
  arcgis_dist_m <- dist_between_coords(samp$LONGITUDE, samp$LATITUDE, samp$arcgis_lon, samp$arcgis_lat)

  dist_summary <- function(d, label) {
    if (length(d) == 0) {
      return(data.frame(source = label, n = 0L, mean_m = NA_real_, median_m = NA_real_, sd_m = NA_real_, p95_m = NA_real_))
    }
    data.frame(
      source   = label,
      n        = length(d),
      mean_m   = mean(d),
      median_m = median(d),
      sd_m     = sd(d),
      p95_m    = as.numeric(quantile(d, 0.95))
    )
  }

  summary_stats <- bind_rows(
    dist_summary(google_dist_m, "Google"),
    dist_summary(arcgis_dist_m, "ArcGIS")
  )

  # Wilcoxon signed-rank (one-sample, mu=0): is median displacement significantly > 0?
  tests <- list()
  if (length(google_dist_m) > 1) tests$google_wilcox  <- wilcox.test(google_dist_m, mu = 0)
  if (length(arcgis_dist_m) > 1) tests$arcgis_wilcox  <- wilcox.test(arcgis_dist_m, mu = 0)

  # Paired Wilcoxon: is one API systematically closer to the original than the other?
  both_valid <- !is.na(samp$google_lon) & !is.na(samp$arcgis_lon)
  if (sum(both_valid) > 1) {
    g_paired <- dist_between_coords(
      samp$LONGITUDE[both_valid], samp$LATITUDE[both_valid],
      samp$google_lon[both_valid], samp$google_lat[both_valid]
    )
    a_paired <- dist_between_coords(
      samp$LONGITUDE[both_valid], samp$LATITUDE[both_valid],
      samp$arcgis_lon[both_valid], samp$arcgis_lat[both_valid]
    )
    if (length(g_paired) == length(a_paired) && length(g_paired) > 1) {
      tests$google_vs_arcgis <- wilcox.test(g_paired, a_paired, paired = TRUE)
    }
  }

  list(
    summary       = summary_stats,
    google_dist_m = google_dist_m,
    arcgis_dist_m = arcgis_dist_m,
    tests         = tests
  )
}

# get food poi data
foodpoic <- read_csv(paste0(processed_path, "foodpoi_2022.csv")) # NEED TO CHANGE TO 2024 data

Sys.getenv("GOOGLE_API_KEY") 
samp <- run_geocoding(foodpoic, google_api_key = GOOGLE_API_KEY, n=1000)

# Step 2 — stats (instant)
res <- summarize_geocoding(samp)
print(res$summary)
print(res$tests)
hist(res$arcgis_dist_m, main = "ArcGIS vs Data Axle displacement (m)", xlab = "Distance (m)", breaks=1000)
hist(res$google_dist_m, main = "Google vs Data Axle displacement (m)", xlab = "Distance (m)", breaks=1000)


# Get results that are very off and plot them
CA <- tigris::states(class = "sf") |> dplyr::filter(STATEFP=="06") 
la_county <- get_county_boundary() %>%
  st_transform(proj_crs)


la_city <- get_city_boundary(proj_crs) %>%
  st_transform(proj_crs)

# --- Map all three coordinate sources ---
orig_sf   <- st_as_sf(samp, coords = c("LONGITUDE",  "LATITUDE"),  crs = 4326) |> dplyr::filter(CITY=="LOS ANGELES")
google_sf <- st_as_sf(samp[!is.na(samp$google_lon), ], coords = c("google_lon",  "google_lat"),  crs = 4326)|> dplyr::filter(CITY=="LOS ANGELES")
arcgis_sf <- st_as_sf(samp[!is.na(samp$arcgis_lon), ], coords = c("arcgis_lon",  "arcgis_lat"),  crs = 4326)|> dplyr::filter(CITY=="LOS ANGELES")

tmap_mode("plot")
tm_shape(la_city) + tm_polygons(col="black") +
tm_shape(orig_sf) + tm_dots(col = "lightblue",  size = 0.2, alpha =.4) +
tm_shape(google_sf) + tm_dots(col = "pink", size = 0.2, alpha =.4) +
tm_shape(arcgis_sf) + tm_dots(col = "green", size = 0.08, alpha =.4) 



