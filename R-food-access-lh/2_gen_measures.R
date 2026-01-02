source("0_Libraries.R")

# ------ CALCULATE PROXIMITY MEASURES ------ #
# proximity_measure <- function (pop_cent, poi, mode='classic') {
  # Calculate proximity measures
# nearest <- st_nearest_feature(pop_cent, poi, check_crs = TRUE)
#  if(mode == 'classic') {
#    dist <- st_distance(pop_cent, poi[nearest,], by_element = TRUE)
#  } else if(mode == 'network') {
    # TODO calculate distance by street network
#  }
  #assign row number of nearest poi to population data
#  pop_cent$nearest_poi <- nearest
#  pop_cent$nearest_dist <- dist
#}

# ------ LOAD ORIGINS ------ #

# load la_hh_cleaned
# get household points from parcel data and clean
la_hh <- get_lac_households(4326)
la_city <- get_city_boundary(proj_crs)
tm_shape(la_city) + tm_borders() # inspect city


la_city_ct <- la_ct %>%
  filter((lengths(st_intersects(., la_city)) > 0)) %>%
  st_transform(4326)

# include households with census tract in la city
la_city_hh <- la_hh %>%
  filter(GEOID_20 %in% la_city_ct$GEOID) %>%
  st_transform(4326)

# la_city_hhn <- la_hh %>%
#   filter(lengths(st_intersects(., la_city)) > 0) %>%
#   st_transform(4326)

# la_ct_map2 <- la_city_ct %>%
#   filter(GEOID %in% as.numeric(la_hh$GEOID_20))
# 
# tm_shape(la_city) +
#   tm_fill(col="green") + 
#   tm_shape(la_ct_map2) +
#   tm_polygons(col = "blue", fill_alpha=.2) 
# 
# temp <- setdiff(as.numeric($GEOID_20), la_hh$GEOID_20)
# # everything is offset incorrectly!!
# check if things are ok still
temp2 <- fc %>% filter(GEOID_20 %in% temp)

notinhh <- la_hh %>% filter(id %in% temp2$id)

head(notinhh)

head(temp)
head(temp2)
  
not_la_cityhh <- la_hh %>%
  filter(!(lengths(st_intersects(., la_city)) > 0)) %>%
  st_transform(4326)

# get census tract centroids and transform them to correct format
la_ctcent_dat <- get_lac_centroids() %>%
  st_transform(4326) %>% # OSM data is in 4326
  mutate(id=row_number()) %>%
  mutate(lon = st_coordinates(.)[,1], lat = st_coordinates(.)[,2])

# make key for id and geoid
la_ct_key <- la_ctcent_dat %>%
  select(id, GEOID) %>%
  st_drop_geometry()

# save key to processed data
write.csv(la_ct_key, paste0(processed_path, "/LAC_origins/la_ct_key.csv"))

# get pop weighted centroids 
la_ct_wtcent_dat <- get_lac_weight_centroids() %>%
  st_transform(4326) %>% # OSM data is in 4326
  merge(la_ct_key, by="GEOID") %>%
  mutate(lon = st_coordinates(.)[,1], lat = st_coordinates(.)[,2])

#!file.exists('../../0_shared-data/processed/LAC_accessibility/density/la_city/parcel_CAR20250321_1800_1.csv')
# setup r5r
data_path <- paste0(base_path, "osm_socal")

r5r_core <- setup_r5(data_path = data_path)

# TODO move into another folder (modular)
# function for computing accessibility measures
compute_accessibility <- function(origins, destinations, mode, chunk_size, cutoffs = c(5, 10, 15, 20, 25, 30, 35, 40, 45), colnames,
                                  origin_type, output_path, file_id = NULL,# used to keep track of files being generated on multiple machines
                                  time_window = 30, departure_time = "2025-03-21 18:00:00", progress = TRUE) {
                                                            
  # Convert departure time to POSIXct
  departure_time <- as.POSIXct(departure_time)
  departure_time_formatted <- format(departure_time, "%Y%m%d_%H%M")
  
  # Construct the output file name
  if (is.null(file_id)) {
    file_name <- paste0(origin_type, "_", mode, departure_time_formatted, ".csv")
    output_file <- paste0(output_path, file_name)
  } else {
    file_name <- paste0(origin_type, "_", mode, departure_time_formatted, "_", file_id, ".csv")
    output_file <- paste0(output_path, file_name)
  }  
  
  print(paste("Will save output to", output_file))
  
  if(!file.exists(output_file)){
    print("Output file doesn't exist, creating now")
    file.create(output_file)  
  }
  
  # Get the number of rows in the origins dataset
  num_rows <- nrow(origins)
  
  # Initialize an empty list to store results
  very_start <- Sys.time()
  
  # Loop through the dataset in chunks
  for (i in seq(1, num_rows, by = chunk_size)) {
    # Define the end index for the current chunk
    end_idx <- min(i + chunk_size - 1, num_rows)
    start <- Sys.time()

    print(paste("Processing rows:", i, "to", end_idx, ">>"))
    print(head(origins[i:end_idx, ]))
    # Compute accessibility for the current chunk
    access_chunk_res <- accessibility(
      r5r_core,
      origins = origins[i:end_idx, ],
      destinations = destinations,
      opportunities_colnames = colnames,
      mode = mode,
      decay_function = "step",
      cutoffs = cutoffs,
      departure_datetime = departure_time,
      time_window = time_window,
      progress = progress
    )
    
    last_idx <<- end_idx # the last index that was processed 
    end <- Sys.time()
    time <- end - start
    total_time <- end - very_start
    print(paste("Processed rows:", i, "to", end_idx, ">>", time))
    print(paste("Total time elapsed:", total_time))

    write.table(access_chunk_res, sep=",", output_file, append=T)
    rJava::.jgc()
  }

  print("Finished processing origins")
  return(output_file)
}

# TODO move this to a different file (e.g. helpers)
setup_access_measure_folders <- function(access_path) { 
  # Setup folder structure 
  measures <- c("proximity", "density", "ratio", "gravity")
  geographies <- c("la_city", "la_county")
  categories <- c("all_markets")
  
  dir.create(access_path)
  
  # create folder for each measure and a folder within each measure for each geography
  for (measure in measures) {
    measure_path <- paste(access_path, measure, sep="/")
    for (geography in geographies) dir.create(paste(measure_path, geography, sep="/"), recursive=T)
  }
  
}

foodpoi <- read.csv(paste0(processed_path, "foodpoi.csv")) %>%
  st_as_sf(coords=c("LONGITUDE", "LATITUDE"), crs=4326)

# TODO move this to a different file (e.g. helpers)
# turn this into function calculating chunk size
calc_chunk_size <- function(ram, mode) { 
  # chunk size
  if (mode == "WALK") dt_chunk <- 1000000 # WALK TIME CHUNK SIZE for 128 GB ram
  else if (mode == "CAR") dt_chunk <- 2000 # DRIVE TIME CHUNK SIZE  for 128 GB ram
  proportion <- ram/128
  chunk_size <- floor(dt_chunk * proportion)  
  return(chunk_size)
  
}

# a line of code for testing funciton 
# access_chunk_res <- compute_accessibility(
#   origins = head(la_ctcent_dat),
#   destinations = head(foodpoi),
#   colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF"),
#   mode = "CAR",
#   origin_type = "test",
#   output_path = paste(access_path, "density/la_city/CATG/", sep="/"),
#   #decay_function = "step",
#   cutoffs = c(5),
#   chunk_size = 10
# )

# testing
head(not_la_cityhh)
empty_points <- st_sfc(rep(list(st_point()), 10), crs = 4326)
sf_obj <- st_sf(id = 1:10, geometry = empty_points)

empty_rows <- la_hh[ ]
head(la_hh)
# 
# access_CAR <- compute_accessibility(
#   origins =  la_hh[1:5,] %>% st_transform(4326),
#   destinations = foodpoi,
#   mode = "CAR",
#   chunk_size = 5, #calc_chunk_size(ram=6, mode="CAR"),#calc_chunk_size(ram=12, mode="WALK"),
#   output_path = paste(access_path, "density/la_city/CATG/", sep="/"),
#   origin_type = "FML",
#   colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
#   #file_id="CAT"
# )
# 
# access_CAR <- compute_accessibility(
#   origins =  not_la_cityhh[1:5,],
#   destinations = foodpoi,
#   mode = "CAR",
#   chunk_size = 5, #calc_chunk_size(ram=6, mode="CAR"),  #calc_chunk_size(ram=12, mode="WALK"),
#   output_path = paste(access_path, "density/la_city/CATG/", sep="/"),
#   origin_type = "FML",
#   colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
#   #file_id="CAT"
# )

access_CAR <- compute_accessibility(
  origins =  la_hh[100:110,] %>% st_transform(4326),
  destinations = foodpoi,
  mode = "CAR",
  chunk_size = 5, #calc_chunk_size(ram=6, mode="CAR"),  #calc_chunk_size(ram=12, mode="WALK"),
  output_path = paste(access_path, "density/la_city/CATG/", sep="/"),
  origin_type = "parcel_notLA",
  colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
  #file_id="CAT"
)

# generate for centroids of census tracts
access_CAR <- compute_accessibility(
  origins =  la_ctcent_dat[2351:nrow(la_ctcent_dat),],
  destinations = foodpoi,
  mode = "CAR",
  chunk_size = 4, #calc_chunk_size(ram=6, mode="CAR"),  #calc_chunk_size(ram=12, mode="WALK"),
  output_path = paste(access_path, "density/la_city/CATG/", sep="/"),
  origin_type = "ct_cent_CAR",
  colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
  #file_id="CAT"
)

# generate for pop weighted centroids 
access_CAR <- compute_accessibility(
  origins =  la_ct_wtcent_dat,
  destinations = foodpoi,
  mode = "CAR",
  chunk_size = 4,#calc_chunk_size(ram=6, mode="CAR"),  #calc_chunk_size(ram=12, mode="WALK"),
  output_path = paste0(access_path, "/density/la_city/CATG/"),
  origin_type = "ct_wtcent_CAR",
  colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF"),
  #file_id="CAT"
)

# generate for parcels
access_CAR <- compute_accessibility(
  origins =  sub,
  destinations = foodpoi,
  mode = "CAR",
  chunk_size = calc_chunk_size(ram=8, mode="CAR"),  #calc_chunk_size(ram=12, mode="WALK"),
  output_path = paste(access_path, "density/la_city/CATG/", sep="/"),
  origin_type = "parcel",
  colnames = c("CNV", "FF", "GRC", "Not included", "RR", "SMK", "SPF"),
  #file_id="CAT"
)

# check progress 
# print(base_path)
access <- read.csv(paste0(processed_path, "LAC_accessibility/density/la_city/", "parcel_CAR20250321_1800_CAT.csv"))
access$id <- as.numeric(access$id) 
access <- access[!is.na(access$id),]
offset <- nrow(access)/5

head(access)
 
# find all ids tht are not in access 
sub <- la_city_hh[!(la_city_hh$id %in% access$id),]
 
 
 
 
