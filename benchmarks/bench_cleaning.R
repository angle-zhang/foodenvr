# benchmarks/bench_cleaning.R
# Benchmarks food POI data cleaning pipeline:
#   Stage B — NAICS categorization (data.table join + dcast)
#   Stage C — Geo-deduplication (st_is_within_distance + Jaro-Winkler)
#
# Run from project root: source("benchmarks/bench_cleaning.R")
#
# Stage B requires Data Axle POI data (proprietary). Export the NAICS lookup
# table once with: write_csv(read_sheet(naics_url), "benchmarks/naics_codes.csv")

source("0_Libraries.R")
source("helper/geo-duplicate-finder.R")
source("benchmarks/bench_helpers.R")

n_dest_vals  <- c(100, 1000, 10000, 100000)
n_replicates <- 5
seed         <- 42
env          <- env_info()

# ---- Stage B: NAICS categorization ----
# Load inputs once outside the timed loop

poi_da <- get_data_axle(year = proj_year, state = proj_state) |>
  filter(!is.na(COMPANY) & !is.na(PRIMARY.SIC.CODE)) |>
  mutate(NAICS.CODE.trunc = as.numeric(str_extract(PRIMARY.NAICS.CODE, "^\\d{1,6}")))

naics_dt <- get_naics(processed_path) |>
  rename(category = `zhang-2025`) |>
  as.data.table()

bench_filename <- paste0("bench_cleaning_", env$timestamp, ".csv")
naics_rows <- list()

for (n in n_dest_vals) {
  set.seed(seed)
  poi_sample <- as.data.table(slice_sample(poi_da, n = min(n, nrow(poi_da))))

  for (rep in seq_len(n_replicates)) {
    t <- run_timed(function() {
      temp <- naics_dt[poi_sample, on = .(code == NAICS.CODE.trunc), nomatch = 0]
      temp[, dummy := 1]
      dcast(
        temp,
        ...1 + COMPANY + ADDRESS.LINE.1 + CITY + ZIPCODE + ZIP4 + LATITUDE + LONGITUDE ~ category,
        value.var = "dummy", fill = 0
      )
    })

    naics_rows[[length(naics_rows) + 1]] <- c(
      list(stage = "naics_categorization", n_origins = NA_integer_, n_destinations = n, replicate = rep),
      t, env
    )
  }
  message("Stage B done: n_dest = ", n)
  write_results(naics_rows, bench_filename)
}

# ---- Stage C: Geo-deduplication ----
# Uses get_dup_candidates() which is the well-defined sub-function:
# spatial neighbor search (st_is_within_distance) + Jaro-Winkler string distance.
# Note: runtime at n=100k may be long due to the O(n^2) worst-case of the spatial index.

foodpoi_sf <- get_foodpoi() |>
  st_as_sf(coords = c("LONGITUDE", "LATITUDE"), crs = proj_coord_crs)

dedup_rows <- list()

for (n in n_dest_vals) {
  set.seed(seed)
  poi_sample <- slice_sample(foodpoi_sf, n = min(n, nrow(foodpoi_sf)))

  for (rep in seq_len(n_replicates)) {
    t <- run_timed(function() {
      get_dup_candidates(poi_sample, name_col = "COMPANY", max_dist_m = 80)
    })

    dedup_rows[[length(dedup_rows) + 1]] <- c(
      list(stage = "geo_deduplication", n_origins = NA_integer_, n_destinations = n, replicate = rep),
      t, env
    )
  }
  message("Stage C done: n_dest = ", n)
  write_results(c(naics_rows, dedup_rows), bench_filename)
}
