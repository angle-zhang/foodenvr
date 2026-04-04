source("0_Libraries.R")
source("./helper/gen-helper.R")

# =============================================================================
# PAPER SECTION C: GENERATING FOOD ENVIRONMENT MEASURES
# Computes network-based food accessibility (density) measures using r5r.
# The compute_accessibility() function wraps r5r::accessibility() with chunked
# processing to prevent data loss from RAM limitations on large origin datasets.
#
# Runs for each combination of:
#   - Population representation: census tract centroids, pop-weighted centroids,
#     household/parcel points
#   - Food retail category: CNV, FF, GRC, RR, SMK, SPF (and Not.included)
#   - Drive-time cutoffs: 5, 10, 15, 20, 25, 30 minutes
#
# Output: chunked CSVs appended to access_path, reassembled in 2_summarize_measures.R
# =============================================================================

# ------ LOAD ORIGINS ------ #

# get household points from parcel data
la_hh <- get_lac_households(4326)
la_city <- get_city_boundary(proj_crs)

la_city_ct <- la_ct %>%
  filter((lengths(st_intersects(., la_city)) > 0)) %>%
  st_transform(4326)

# include households with census tract in la city
la_city_hh <- la_hh %>%
  filter(GEOID_20 %in% la_city_ct$GEOID) %>%
  st_transform(4326)

# get census tract centroids and transform to CRS 4326 required by r5r
la_ctcent_dat <- get_lac_centroids() %>%
  st_transform(4326) %>%
  mutate(id = row_number()) %>%
  mutate(lon = st_coordinates(.)[,1], lat = st_coordinates(.)[,2])

# make key for id and geoid
la_ct_key <- la_ctcent_dat %>%
  select(id, GEOID) %>%
  st_drop_geometry()

# save key to processed data
write.csv(la_ct_key, paste0(processed_path, "/LAC_origins/la_ct_key.csv"))

# get pop weighted centroids
la_ct_wtcent_dat <- get_lac_weight_centroids() %>%
  st_transform(4326) %>%
  merge(la_ct_key, by = "GEOID") %>%
  mutate(lon = st_coordinates(.)[,1], lat = st_coordinates(.)[,2])


# ------ GENERATE ACCESSIBILITY MEASURES ------ #
# Run compute_accessibility() for each population representation method.
# chunk_size is set conservatively; adjust using calc_chunk_size() based on available RAM.

# generate for census tract centroids
access_CAR <- compute_accessibility(
  origins = la_ctcent_dat,
  destinations = foodpoi,
  mode = "CAR",
  chunk_size = 4, # calc_chunk_size(ram=6, mode="CAR")
  output_path = paste0(access_path, "/density/la_city/CATG/"),
  origin_type = "ct_cent_CAR",
  colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
)

# generate for population-weighted census tract centroids
access_CAR <- compute_accessibility(
  origins = la_ct_wtcent_dat,
  destinations = foodpoi,
  mode = "CAR",
  chunk_size = 4, # calc_chunk_size(ram=6, mode="CAR")
  output_path = paste0(access_path, "/density/la_city/CATG/"),
  origin_type = "ct_wtcent_CAR",
  colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
)

# generate for parcels (households)
access_CAR <- compute_accessibility(
  origins = la_city_hh,
  destinations = foodpoi,
  mode = "CAR",
  chunk_size = calc_chunk_size(ram = 8, mode = "CAR"),
  output_path = paste0(access_path, "/density/la_city/CATG/"),
  origin_type = "parcel",
  colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
)

# check progress: read output file and find unprocessed ids
# access <- read.csv(paste0(access_path, "/density/la_city/CATG/parcel_CAR<datetime>.csv"))
# access$id <- as.numeric(access$id)
# access <- access[!is.na(access$id), ]
# offset <- nrow(access) / 5  # number of origins processed (5 food categories)
# sub <- la_city_hh[!(la_city_hh$id %in% access$id), ]  # remaining unprocessed origins
