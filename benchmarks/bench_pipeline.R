# benchmarks/bench_pipeline.R
# Benchmarks the post-compute pipeline stages:
#   Stage A — origin loading (get_lac_households, timed once at actual dataset size)
#   Stage E — file merge (get_and_merge_files, synthetic chunked CSVs)
#   Stage E2 — relative measures (calc_relative_measures)
#   Stage F — reshape + census-tract aggregation (process_times)
#
# Run from project root: source("benchmarks/bench_pipeline.R")

source("0_Libraries.R")
source("helper/gen-helper.R")
source("benchmarks/bench_helpers.R")

n_origins_vals  <- c(100, 1000, 10000, 100000)
n_replicates    <- 5
seed            <- 42
env             <- env_info()
opportunities   <- c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
cutoffs         <- c(5, 10, 15)

# ---- Stage A: origin loading (timed once, actual full dataset) ----
origin_timing <- run_timed(function() {
  la_hh <<- get_lac_households(processed_path, proj_coord_crs)
})
message(sprintf("Stage A: loaded %d households in %.1f s", nrow(la_hh), origin_timing$wall_s))

origin_row <- c(
  list(stage = "origin_loading", n_origins = nrow(la_hh), n_destinations = NA_integer_, replicate = 1L),
  origin_timing, env
)

# ---- Helper: generate synthetic chunked CSVs matching get_and_merge_files() format ----
make_synthetic_chunks <- function(n_orig, out_dir, n_chunks = 4) {
  chunk_size <- ceiling(n_orig / n_chunks)
  for (chunk_i in seq_len(n_chunks)) {
    ids <- seq((chunk_i - 1) * chunk_size + 1, min(chunk_i * chunk_size, n_orig))
    df  <- expand.grid(id = ids, opportunity = opportunities, percentile = 50, cutoff = cutoffs,
                       stringsAsFactors = FALSE)
    df$accessibility <- runif(nrow(df))
    df$row.names     <- seq_len(nrow(df))
    write.table(df[, c("row.names", "id", "opportunity", "percentile", "cutoff", "accessibility")],
                sep = ",",
                file.path(out_dir, sprintf("bench_parcel_CAR20250321_1800_%d.csv", chunk_i)),
                row.names = FALSE)
  }
}

# ---- Helper: synthetic GEOID key ----
# TODO use actual GEOID key 
make_ct_key <- function(n_orig) {
  set.seed(seed)
  data.frame(
    id    = seq_len(n_orig),
    GEOID = paste0("0603710", formatC(sample.int(9999, n_orig, replace = TRUE), width = 4, flag = "0"))
  )
}

# ---- Stages E, E2, and F ----
bench_filename  <- paste0("bench_pipeline_", env$timestamp, ".csv")
merge_rows      <- list()
relative_rows   <- list()
reshape_rows    <- list()

for (n in n_origins_vals) {
  tmp_dir <- file.path(tempdir(), paste0("bench_chunks_", n))
  dir.create(tmp_dir, showWarnings = FALSE)
  make_synthetic_chunks(n, tmp_dir)

  ct_key <- make_ct_key(n)

  for (rep in seq_len(n_replicates)) {

    # Stage E: file merge
    t_merge <- run_timed(function() {
      merged <<- get_and_merge_files(tmp_dir, "bench_parcel_CAR")
    })
    merge_rows[[length(merge_rows) + 1]] <- c(
      list(stage = "file_merge", n_origins = n, n_destinations = NA_integer_, replicate = rep),
      t_merge, env
    )

    # Stage E2: relative measures
    t_relative <- run_timed(function() {
      merged_rel <<- calc_relative_measures(merged)
    })
    relative_rows[[length(relative_rows) + 1]] <- c(
      list(stage = "relative_measures", n_origins = n, n_destinations = NA_integer_, replicate = rep),
      t_relative, env
    )

    # Stage F: reshape wide + census-tract aggregation
    t_reshape <- run_timed(function() {
      process_times(merged_rel |> select(-row.names), ct_key,
                    GEOID = "GEOID", type = "driving", scale = "parcel", time = 15, agg = TRUE)
    })
    reshape_rows[[length(reshape_rows) + 1]] <- c(
      list(stage = "reshape_aggregate", n_origins = n, n_destinations = NA_integer_, replicate = rep),
      t_reshape, env
    )

    gc()
  }

  unlink(tmp_dir, recursive = TRUE)
  message("Pipeline stages done: n_origins = ", n)
  write_results(c(list(origin_row), merge_rows, relative_rows, reshape_rows), bench_filename)
}
