# benchmarks/bench_accessibility.R
# Benchmarks compute_accessibility() over specific origin x destination pairs,
# with each cutoff (5, 10, 15 min) timed separately.
#
# Results table rows:    100x100, 1000x1000, 10k x 10k, 100k x 100k, 1M x 100k
# Results table columns: wall_s at cutoff 5, 10, 15
#
# Run from project root: source("benchmarks/bench_accessibility.R")
#
# Sourcing helper/gen-helper.R triggers setup_r5(), which is the one-time JVM
# initialisation cost. That cost is timed separately before the grid loop.

source("0_Libraries.R")
source("benchmarks/bench_helpers.R")

library(r5r)
pairs <- list(
 c(100,     100),
 c(1000,    1000),
 c(10000,   10000)#,
 # c(100000,  100000)#,
  #c(1000000, 100000)
)
cutoffs         <- c(5, 10, 15)
seed            <- 42
food_categories <- c("CNV", "FF", "GRC", "RR", "SMK", "SPF")
env             <- env_info()

# ---- r5r setup (timed once, not included in per-cell timings) ----
data_path <- paste0(base_path, "geo_", proj_county)
setup_timing <- run_timed(function() {
  r5r_core <<- setup_r5(data_path = data_path)
})
message(sprintf("r5r setup: %.1f s", setup_timing$wall_s))

source("helper/gen-helper.R")  # defines compute_accessibility; r5r_core already set above

# ---- Load and prepare origin/destination pools ----
la_city_hh <- {
  la_ct    <- get_census_tracts(base_path, crs = proj_crs, state = proj_state, year = proj_year, county = proj_county)
  la_city  <- get_city_boundary(proj_crs)
  city_geoids <- la_ct %>%
    filter(lengths(st_intersects(., la_city)) > 0) |>
    pull(GEOID)
  get_lac_households(processed_path, proj_coord_crs) |>
    filter(GEOID_20 %in% city_geoids)
}

foodpoi_sf <- get_foodpoi() |>
  st_as_sf(coords = c("LONGITUDE", "LATITUDE"), crs = proj_coord_crs)

n_reps <- function(n_orig, n_dest) if (n_orig >= 10000 | n_dest >= 10000) 1L else 1L

# ---- Benchmark grid ----
bench_filename <- paste0("bench_accessibility_", env$timestamp, ".csv")

rows <- list(c(
  list(stage = "r5r_setup", n_origins = NA_integer_, n_destinations = NA_integer_, cutoff = NA_integer_, replicate = 1L),
  setup_timing, env
))

for (pair in pairs) {
  n_orig <- pair[1]
  n_dest <- pair[2]

  set.seed(seed)
  origins      <- slice_sample(la_city_hh, n = min(n_orig, nrow(la_city_hh)))
  destinations <- slice_sample(foodpoi_sf,  n = min(n_dest, nrow(foodpoi_sf)))

  for (cutoff in cutoffs) {
    for (rep in seq_len(n_reps(n_orig, n_dest))) {
      t <- run_timed(function() {
        compute_accessibility(
          origins      = origins,
          destinations = destinations,
          mode         = "CAR",
          chunk_size   = min(n_orig, 500L),
          cutoffs      = cutoff,
          colnames     = food_categories,
          origin_type  = sprintf("bench_%d_%d_%d_%d", n_orig, n_dest, cutoff, rep),
          output_path  = tempdir()
        )
      })

      rows[[length(rows) + 1]] <- c(
        list(stage = "accessibility", n_origins = n_orig, n_destinations = n_dest, cutoff = cutoff, replicate = rep),
        t, env
      )

      rJava::.jgc()
      gc()
    }

    message(sprintf("Accessibility done: n_orig = %d, n_dest = %d, cutoff = %d min", n_orig, n_dest, cutoff))
  }

  write_results(rows, bench_filename)
}
