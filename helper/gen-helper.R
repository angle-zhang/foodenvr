# Java setup — options(java.parameters) must be set before library(r5r)
# run once on SSI lab computers:
#   library(rJavaEnv); java_quick_install(version = 21)
#   Sys.setenv(JAVA_HOME="C:\\Users\\lab.DTS-MJ0LQJJJ\\AppData\\Local//R//cache//R//rJavaEnv//installed//windows//x64//21")
# on personal machines:
#   Sys.setenv(JAVA_HOME="C:\\Program Files\\Java\\jdk-21")
rJavaEnv::java_check_version_rjava()
options(java.parameters = "-Xmx12G")
library(r5r)

# setup r5r
data_path <- paste0(base_path, "geo_", proj_county)

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
  st_as_sf(coords=c("LONGITUDE", "LATITUDE"), crs=proj_coord_crs)

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

weighted_median <- function(x, w) {
  na_idx <- is.na(x) | is.na(w)
  x <- x[!na_idx]; w <- w[!na_idx]
  if (length(x) == 0) return(NA_real_)
  ord <- order(x)
  x <- x[ord]; w <- w[ord]
  x[which(cumsum(w) / sum(w) >= 0.5)[1]]
}

# population-weighted sd (divides by sum(w), appropriate for full household population)
weighted_sd <- function(x, w) {
  na_idx <- is.na(x) | is.na(w)
  x <- x[!na_idx]; w <- w[!na_idx]
  if (length(x) == 0) return(NA_real_)
  wm <- weighted.mean(x, w)
  sqrt(sum(w * (x - wm)^2) / sum(w))
}

get_and_merge_files <- function(path, pattern, col.names=c("row.names", "id", "opportunity", "percentile", "cutoff", "accessibility")){
  files <- list.files(path = path, pattern = pattern, full.names = TRUE) 
  print(files)
  print("Reading CSVs")
  data <- lapply(files, fread, col.names=col.names, fill=T, header=T)
  
  print("binding data")
  data <- rbindlist(data, use.names=FALSE)
  
  print("finishing up...")
  
  # print(problems(data))
  print("cleaning...")
  data$id <- as.numeric(data$id) 
  print("remove NAs from col names")
  data <- data[!is.na(data$id),] #remove IDs that are nas due to their presence as col names 
  return(data)
}

# create a function that can be used to process the data for both driving and walking times
# data is merged with spatial data and columns are slightly altered
# data is also potentially aggregated into a larger spatial scale
# time = max time distance of data desired
# agg = aggregate
process_times <- function(data, merge_data, GEOID="GEOID", type, scale, time=15, agg=F, weight_col=NULL){
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
    mutate(GEOID := as.character(get(!!GEOID)))

  keep_cols <- c("id", "GEOID", if (!is.null(weight_col)) weight_col)
  geoid_joined <- geoid_joined %>% select(all_of(keep_cols), starts_with(type))
  
  #print(geoid_joined$GEOID)
  
  if (agg==TRUE) {
    print("Aggregating parcels into census-level data...")

    base_df <- geoid_joined %>%
      select(-id) %>%
      st_drop_geometry()

    measure_cols <- names(base_df)[startsWith(names(base_df), type)]

    ct_unweighted <- base_df %>%
      group_by(GEOID) %>%
      summarise(across(all_of(measure_cols), list(
        mean   = ~mean(., na.rm = TRUE),
        median = ~median(., na.rm = TRUE),
        sd     = ~sd(., na.rm = TRUE)
      ))) %>%
      ungroup()

    if (!is.null(weight_col)) {
      ct_weighted <- base_df %>%
        group_by(GEOID) %>%
        summarise(across(all_of(measure_cols), list(
          w_mean   = \(x) weighted.mean(x, w = pick(all_of(weight_col))[[1]], na.rm = TRUE),
          w_median = \(x) weighted_median(x, pick(all_of(weight_col))[[1]]),
          w_sd     = \(x) weighted_sd(x, pick(all_of(weight_col))[[1]])
        ))) %>%
        ungroup()

      ct_summary_meas <- left_join(ct_unweighted, ct_weighted, by = "GEOID")
    } else {
      ct_summary_meas <- ct_unweighted
    }

    print(head(ct_summary_meas))
    return(ct_summary_meas)
  }
  
  return(geoid_joined)
}

calc_relative_measures <- function(full_data) {
  setDT(full_data)
  totals <- full_data |>
    mutate(accessibility=as.numeric(accessibility)) |>
    filter(opportunity %in% c("CNV", "GRC", "SMK", "SPF", "FF", "RR")) |>
    summarize(
      AFS_val = sum(accessibility[opportunity %in% c("CNV", "GRC", "SMK", "SPF")], na.rm = TRUE),
      ARR_val = sum(accessibility[opportunity %in% c("FF", "RR")], na.rm = TRUE),
      .by = c(id, percentile, cutoff)
    )
  
  # 2. Merge totals back to original data to calculate Ratios
  # We engage a 'left_join' to bring those sums next to the rows
  ratios <- full_data |>
    mutate(accessibility=as.numeric(accessibility)) |>
    filter(opportunity %in% c("SMK", "RR")) |> # We only need these rows to calc ratios
    # TODO use FF restaurant
    left_join(totals, by = c("id", "percentile", "cutoff")) |>
    mutate(
      # Create the ratio rows, renaming them as we go
      RELSMK = if_else(AFS_val == 0, 0, accessibility / AFS_val),
      RELRR  = if_else(ARR_val == 0, 0, accessibility / ARR_val)
    ) |>
    select(row.names, id, percentile, cutoff, opportunity, RELSMK, RELRR) |>
    # Reshape these specific ratio columns to be 'long' like the main data
    pivot_longer(c(RELSMK, RELRR), names_to = "new_opp", values_to = "new_acc") |>
    # Keep only the matching pairs (e.g. discard the RELRR calculation for the SMK row)
    filter(
      (opportunity == "SMK" & new_opp == "RELSMK") |
        (opportunity == "RR"  & new_opp == "RELRR") # TODO generate fast food restaurant measure
    ) |>
    select(-opportunity) |>
    rename(opportunity = new_opp, accessibility = new_acc)
  
  # 3. Format the totals to look like the main data
  totals_long <- totals |>
    pivot_longer(c(AFS_val, ARR_val), names_to = "opportunity", values_to = "accessibility") |>
    mutate(opportunity = if_else(opportunity == "AFS_val", "AFS", "ARR"))
  
  # 4. Bind it all together (Original + Totals + Ratios)
  final_result <- bind_rows(full_data, totals_long, ratios)
  
  # Optional: Clean up memory
  rm(totals, ratios, totals_long)
  gc() # Force garbage collection
  
  return(final_result)
}