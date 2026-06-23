library(testthat)
source("0_Libraries.R")
source("helper/data_functions.R")

la_city <- get_city_boundary(proj_crs)
la_ct   <- get_census_tracts(base_path, proj_crs, state = STUDY_STATE, year = STUDY_YEAR, county = STUDY_COUNTY) |>
  mutate(GEOID = as.character(GEOID)) |>
  st_as_sf()

# get_dense_inset_boxes ---------------------------------------------------

test_that("returns 2 boxes by default", {
  result <- get_dense_inset_boxes(la_city, la_ct, STUDY_STATE, STUDY_COUNTY, STUDY_YEAR, proj_crs)
  expect_length(result, 2)
  expect_named(result, c("box1", "box2"))
})

test_that("n is derived from buffer_sizes length when not supplied", {
  result <- get_dense_inset_boxes(la_city, la_ct, STUDY_STATE, STUDY_COUNTY, STUDY_YEAR, proj_crs,
                                  buffer_sizes = c(4500, 4500, 4500))
  expect_length(result, 3)
  expect_named(result, c("box1", "box2", "box3"))
})

test_that("explicit n overrides buffer_sizes length", {
  result <- get_dense_inset_boxes(la_city, la_ct, STUDY_STATE, STUDY_COUNTY, STUDY_YEAR, proj_crs,
                                  buffer_sizes = c(4500, 4500, 4500), n = 2)
  expect_length(result, 2)
  expect_named(result, c("box1", "box2"))
})

test_that("all boxes are sfc polygons in the correct CRS", {
  result <- get_dense_inset_boxes(la_city, la_ct, STUDY_STATE, STUDY_COUNTY, STUDY_YEAR, proj_crs,
                                  buffer_sizes = c(4500, 4500, 4500))
  for (box in result) {
    expect_true(inherits(box, "sfc"))
    expect_equal(st_crs(box), st_crs(proj_crs))
  }
})

test_that("box centers are separated by at least min_separation_m", {
  min_sep <- 10000
  result  <- get_dense_inset_boxes(la_city, la_ct, STUDY_STATE, STUDY_COUNTY, STUDY_YEAR, proj_crs,
                                   buffer_sizes = c(4500, 4500, 4500), min_separation_m = min_sep)
  centers <- lapply(result, st_centroid)
  pairs   <- combn(length(centers), 2, simplify = FALSE)
  for (p in pairs) {
    d <- as.numeric(st_distance(centers[[p[1]]], centers[[p[2]]]))
    expect_gt(d, min_sep, label = paste("distance between box", p[1], "and box", p[2]))
  }
})

test_that("all boxes fall within or near the city boundary", {
  result      <- get_dense_inset_boxes(la_city, la_ct, STUDY_STATE, STUDY_COUNTY, STUDY_YEAR, proj_crs,
                                       buffer_sizes = c(4500, 4500, 4500))
  city_buf    <- st_buffer(la_city, 5000)
  for (nm in names(result)) {
    center <- st_centroid(result[[nm]])
    expect_true(
      as.logical(st_within(center, city_buf)),
      label = paste(nm, "center is within 5 km of city boundary")
    )
  }
})

