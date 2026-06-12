# benchmarks/run_all.R
# Runs all benchmark scripts and merges results into a single CSV.
# Run from project root: source("benchmarks/run_all.R")
#
# bench_accessibility.R is the slowest step (~hours for large cells).
# Set RUN_ACCESSIBILITY=FALSE to skip it during development.

RUN_ACCESSIBILITY <- FALSE

source("benchmarks/bench_cleaning.R")
source("benchmarks/bench_pipeline.R")

if (RUN_ACCESSIBILITY) {
  source("benchmarks/bench_accessibility.R")
}
# Merge all result CSVs (excluding previously combined files)
result_files <- result_files[!grepl("all_benchmarks", result_files)]

print(result_files)

read_with_source <- function(f) {
  df <- read.csv(f, stringsAsFactors = FALSE)
  df$source_file <- sub("_\\d{8}_\\d{6}\\.csv$", "", basename(f))
  df
}
combined <- do.call(bind_rows, lapply(result_files, read_with_source))

# Step 1: mean across replicates for each stage
# cutoff is only present in bench_accessibility; cleaning/pipeline rows will have cutoff = NA
stage_means <- combined %>%
  group_by(source_file, stage, n_origins, n_destinations, cutoff) %>%
  summarise(wall_s_mean       = mean(wall_s,        na.rm = TRUE),
            cpu_s_mean        = mean(cpu_s,          na.rm = TRUE),
            rss_delta_mb_mean = mean(rss_delta_mb,   na.rm = TRUE),
            .groups = "drop")

# Step 2: sum stage means within each source file → mean total time per file
file_totals <- stage_means %>%
  group_by(source_file, n_origins, n_destinations, cutoff) %>%
  summarise(wall_s_total      = sum(wall_s_mean, na.rm = TRUE),
            cpu_s_total       = sum(cpu_s_mean,  na.rm = TRUE),
            .groups = "drop")

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_path  <- file.path("benchmarks", "results", paste0("all_benchmarks_", timestamp, ".csv"))
write.csv(file_totals, out_path, row.names = FALSE)
message("Combined results written to ", out_path)

