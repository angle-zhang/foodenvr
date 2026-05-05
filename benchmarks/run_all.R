# benchmarks/run_all.R
# Runs all benchmark scripts and merges results into a single CSV.
# Run from project root: source("benchmarks/run_all.R")
#
# bench_accessibility.R is the slowest step (~hours for large cells).
# Set RUN_ACCESSIBILITY=FALSE to skip it during development.

RUN_ACCESSIBILITY <- TRUE

source("benchmarks/bench_cleaning.R")
source("benchmarks/bench_pipeline.R")

if (RUN_ACCESSIBILITY) {
  source("benchmarks/bench_accessibility.R")
}
# Merge all result CSVs written during this session into one combined file
result_files <- list.files("benchmarks/results", pattern = "\\.csv$", full.names = TRUE)
combined <- do.call(rbind, lapply(result_files, read.csv, stringsAsFactors = FALSE))

timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_path  <- file.path("benchmarks", "results", paste0("all_benchmarks_1", timestamp, ".csv"))
write.csv(combined, out_path, row.names = FALSE)
message("Combined results written to ", out_path)

