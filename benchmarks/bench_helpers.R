# benchmarks/bench_helpers.R
# Shared utilities for all benchmark scripts.

library(ps)

rss_mb <- function() {
  tryCatch(ps_memory_info()$rss / 1024^2, error = function(e) NA_real_)
}

run_timed <- function(fn, ...) {
  gc()
  mem_before <- rss_mb()
  t0 <- proc.time()
  fn(...)
  elapsed <- proc.time() - t0
  list(
    wall_s       = unname(elapsed["elapsed"]), # elapsed seconds wall-clock time
    cpu_s        = unname(elapsed["user.self"]), # elapsed seconds in CPU time
    rss_delta_mb = rss_mb() - mem_before
  )
}

env_info <- function() {
  list(
    timestamp   = format(Sys.time(), "%Y%m%d_%H%M%S"),
    git_sha     = tryCatch(trimws(system("git rev-parse --short HEAD", intern = TRUE)), error = function(e) NA_character_),
    r_version   = paste(R.version$major, R.version$minor, sep = "."),
    r5r_version = tryCatch(as.character(packageVersion("r5r")), error = function(e) NA_character_),
    ram_gb      = tryCatch(round(ps_system_memory()$total / 1024^3, 1), error = function(e) NA_real_),
    platform    = Sys.info()[["sysname"]]
  )
}

write_results <- function(rows, filename) {
  df <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  path <- file.path("benchmarks", "results", filename)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write.csv(df, path, row.names = FALSE)
  message("Wrote ", nrow(df), " rows to ", path)
  invisible(df)
}
