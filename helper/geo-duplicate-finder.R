# TODO publish as an R package - POI cleaning assist package

# TODO Remove common words like "restaurant" or "market"
# TODO Add additional filter - duplicates must come from a similar category - unsure if this is necessary or helpful (need to see)
# TODO Weight the similarity (i.e. some names have lower similarity, but if the distance is 0, they may be likely to have the same similarity)

find_geo_duplicates <- function(data, name_col = "COMPANY", max_dist_m = 80, jw_threshold = .9) {
  
  require(stringdist)
  
  data <- foodpoi
  name_col = "COMPANY"
  max_dist_m = 40  # 50 - 269 dups
  jw_threshold = .9
  
  if(!inherits(data, "sf")) { 
    print("transforming data to coordinates")
    data <- st_as_sf(data, coords = c("LONGITUDE", "LATITUDE"), crs=4326)
  }
  
  # Step 1: find all pairs of points within max_dist_m (spatial filter)
  # TODO this may take longer; try to find matching string pairs first 
  nearby <- st_is_within_distance(data, dist = max_dist_m, sparse = TRUE)
  nearby <-  st_is_within_distance(data, dist = 50, sparse = TRUE)
  # Build a data frame of candidate pairs, keeping only i < j to avoid double-counting
  pair_list <- vector("list", length(nearby))
  for (i in seq_along(nearby)) {
    js <- nearby[[i]][nearby[[i]] > i] # list item gets saved if list item is GREATER than i 
    if (length(js) > 0) pair_list[[i]] <- data.frame(i = i, j = js) # list item gets saved if more than one pair
  }
  pairs <- bind_rows(pair_list) # GROUP ALL PAIRS
  
  message(sprintf("Found %d pairs within %dm distance", nrow(pairs), max_dist_m))
  
  if (is.null(pairs) || nrow(pairs) == 0) {
    message("No nearby pairs found.")
    return(st_transform(data, original_crs))
  }
  
  # Step 2: compute Jaro-Winkler similarity on names for candidate pairs
  # TODO add additional match case - if address is exact same and name of restaurant is similar
  names_vec <- data[[name_col]]
  pairs$jw_sim <- 1 - stringdist(names_vec[pairs$i], names_vec[pairs$j], method = "jw")
  
  # Step 3: Find pairs that also pass the name-similarity threshold
  dupe_pairs <- pairs[pairs$jw_sim >= jw_threshold, ]
  
  if (nrow(dupe_pairs) == 0) {
    message("No duplicates found.")
    return(st_transform(data, original_crs))
  }
  
  # Step 4: remove the second record in each duplicate pair
  to_remove <- unique(dupe_pairs$j)

  message(sprintf(
    "Removing %d duplicate(s) (within %dm, JW similarity >= %.2f).",
    length(to_remove), max_dist_m, jw_threshold
  ))
  
  dupl_idx <- dupe_pairs |>
    mutate(dup_ID = row_number()) |> 
    pivot_longer(cols=c(i, j), names_to="pair", values_to = "row_n")
  
  data1 <- data |> 
    mutate(row_n = row_number())
  
  data1 <- left_join(data1, dupl_idx, by="row_n") |> 
    arrange(dup_ID) |> 
    select(dup_ID, everything()) |> st_drop_geometry()

    
#    [dupl_idx$i==data1$row_n, "ID"]
    # TODO FUture plans - Step 5: 
  # Return list with dataframe that has duplicates removed and duplicates 
  results <- list(data1[-to_remove,], data1[!is.na(data1$dup_ID),])
  return(results)  
}

# Returns all candidate duplicate pairs as a long data frame (2 rows per pair)
# so you can inspect original records and choose thresholds interactively.
# Filter the output by dist_m and jw_sim to see what different thresholds capture.
#
#' /* Usage:*/
# candidates <- get_dup_candidates(foodpoi)
# 
# # inspect what a 50m / 0.9 threshold catches
# threshold_candidates <- candidates |> filter(dist_m <= 100, jw_sim >= 0.8)
# 
# # compare counts across thresholds
# candidates |>
#   filter(pair_role == "keep") |>   # one row per pair
#   summarise(
#     `50m_0.9`  = sum(dist_m <= 50  & jw_sim >= 0.9),
#     `80m_0.9`  = sum(dist_m <= 80  & jw_sim >= 0.9),
#     `50m_0.85` = sum(dist_m <= 50  & jw_sim >= 0.85)
#   )
get_dup_candidates <- function(data, name_col = "COMPANY", max_dist_m = 100) {
  if (!inherits(data, "sf")) {
    data <- st_as_sf(data, coords = c("LONGITUDE", "LATITUDE"), crs = 4326)
  }

  nearby <- st_is_within_distance(data, dist = max_dist_m, sparse = TRUE)

  pair_list <- vector("list", length(nearby))
  for (i in seq_along(nearby)) {
    js <- nearby[[i]][nearby[[i]] > i]
    if (length(js) > 0) pair_list[[i]] <- data.frame(i = i, j = js)
  }
  pairs <- bind_rows(pair_list)

  if (nrow(pairs) == 0) {
    message("No nearby pairs found.")
    return(NULL)
  }

  names_vec     <- data[[name_col]]
  pairs$dist_m  <- as.numeric(st_distance(data[pairs$i, ], data[pairs$j, ], by_element = TRUE))
  pairs$jw_sim  <- 1 - stringdist(names_vec[pairs$i], names_vec[pairs$j], method = "jw")
  pairs$pair_id <- seq_len(nrow(pairs))

  # Long format: one row per record in each pair, labelled keep/remove
  keep_rows   <- data[pairs$i, ] |> st_drop_geometry() |> mutate(pair_id = pairs$pair_id, pair_role = "keep",   dist_m = pairs$dist_m, jw_sim = pairs$jw_sim)
  remove_rows <- data[pairs$j, ] |> st_drop_geometry() |> mutate(pair_id = pairs$pair_id, pair_role = "remove", dist_m = pairs$dist_m, jw_sim = pairs$jw_sim)

  bind_rows(keep_rows, remove_rows) |>
    arrange(pair_id, pair_role, dist_m, jw_sim) |>
    select(pair_id, pair_role, dist_m, jw_sim, everything())
}
# 

