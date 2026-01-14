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
  print(paste0("Saved to file: ", output_file))
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

# Helper functions: Merging files and aggregating to geographically specific level  -------------------------------
#'@get_and_merge_files: get all files with a particular format and combine them into one file for processing
#'@process_times: function that can be used to aggregate the data to a certain geographic specificity

get_and_merge_files <- function(path, pattern, col.names=c("row.names", "id", "opportunity", "percentile", "cutoff", "accessibility")){
  files <- list.files(path = path, pattern = pattern, full.names = TRUE) 
  print(files)
  print("Reading CSVs")
  data <- lapply(files, fread, col.names=col.names, fill=T, header=T)
  # TODO make this faster...
  
  print("binding data")
  data <- rbindlist(data, use.names=FALSE)
  print("finishing up...")
  
  # print(problems(data))
  data$id <- as.numeric(data$id) 
  data <- data[!is.na(data$id),] #remove IDs that are nas due to their presence as col names 
  return(data)
}

# create a function that can be used to process the data for both driving and walking times
# data is merged with spatial data and columns are slightly altered
# data is also potentially aggregated into a larger spatial scale
# time = max time distance of data desired
# agg = aggregate
process_times <- function(data, merge_data, GEOID="GEOID", type, scale, time=15, agg=F){
  # print(head(data))
  # print(head(geoid_key))
  data <- data %>%
    unique() %>%
    filter(as.numeric(cutoff) <= time) %>%
    mutate(id = as.numeric(id), 
           opportunity = paste0(type, "_", opportunity), 
           accessibility = as.numeric(accessibility),
           scale = scale) |>
    select(-percentile)
  
  print(head(data))
  data <- data |>
    as.data.table() |>
    dcast(id ~ opportunity + cutoff + scale, value.var="accessibility") |> 
    mutate(id=as.numeric(id)) |>
    as.data.frame()
  
  names(data) <- sub(" ", ".", names(data))
  print(head(data))
  
  geoid_joined <- merge_data %>%
    mutate(id = as.numeric(id)) |>
    left_join(data, by = "id") %>% # join data with other data
    mutate(GEOID := as.numeric(get(!!GEOID))) %>%
    select(id, GEOID, starts_with(type))
  
  #print(geoid_joined$GEOID)
  
  if (agg==TRUE) {
    # merge by id col to la_city_hh and aggregate to census tract level
    print("Aggregating parcels into census-level data...")
    # aggregate all columns with driving to census tract level
    ct_summary_meas <- geoid_joined %>%
      select(-id) %>%
      st_drop_geometry() %>%
      group_by(GEOID) %>%
      summarise(across(where(is.numeric),
                       list(
                         mean   = ~mean(., na.rm = TRUE),
                         median = ~median(., na.rm = TRUE),
                         sd = ~sd(., na.rm = TRUE),
                         cv = ~sd(., na.rm = TRUE) / mean(., na.rm = TRUE) * 100
                       ))) %>%
      ungroup()
    
    print(head(ct_summary_meas))
    
    return(ct_summary_meas)
  }
  
  return(geoid_joined)
}
