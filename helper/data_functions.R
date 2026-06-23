# TODO change to new file
calc_pop_weighted_centroid <- function(geo_data, group_col, weight_col) {
  # get centroid of blocks and remove empty geometries
  res <- geo_data %>%
    subset(!st_is_empty(.)) %>%
    st_make_valid() %>%
    st_centroid_within_poly() %>% # get the centroid within the block first 
    mean_center(group=group_col, weight=weight_col)
  
  geom_col_name <- attr(res, "sf_column")
  
  if(geom_col_name == "geom") res <- res %>% rename(geometry=geom)
  
  return(res)
}

# from stack overflow
# TODO change behaivor from st_point_on_surface

st_centroid_within_poly <- function (poly) {
  # check if centroid is in polygon
  ctrd <- st_centroid(poly)
  ctrd$indicator <- st_within(ctrd, poly, sparse = T) %>% lengths > 0
  # replace geometries that are not within polygon with st_point_on_surface()
  st_geometry(ctrd[!ctrd$indicator,]) <- st_geometry(st_point_on_surface(poly[!ctrd$indicator,])) # gets the centroid within a polygon (guaranteed)
  ctrd %>% select(-indicator)
}


clipintersect_boundary <- function(result, boundary, buffer = 0) {
  boundary1 <- st_buffer(boundary, buffer)

  result1 <- result %>%
    dplyr::filter(lengths(st_intersects(., boundary1)) > 0) %>%
    st_intersection(boundary1)

  return(result1)
}

# Shared ggplot map theme — used in 1_visualizations.Rmd and 3_prelim_results.Rmd
theme_map <- theme_void(base_size = 9) +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    legend.position = "right",
    legend.title    = element_text(size = 8, face = "bold"),
    legend.text     = element_text(size = 7),
    plot.title      = element_text(size = 10, face = "bold", hjust = 0.5),
    plot.margin     = margin(5, 5, 5, 5)
  )

# Returns a named list of n bounding boxes around the n densest population clusters in la_city,
# each guaranteed to be at least min_separation_m from previously chosen centers.
# buffer_sizes: numeric vector of length n — one buffer radius (metres) per box.
get_dense_inset_boxes <- function(la_city, la_ct, state, county, year, proj_crs,
                                   buffer_sizes = rep(6000, 2), n = length(buffer_sizes), min_separation_m = 10000) {
  ct_pop <- tidycensus::get_acs(
    geography = "tract", variables = "B01003_001",
    state = state, county = county, year = year, progress = FALSE
  )

  ct_dens <- la_ct %>%
    mutate(GEOID = as.character(GEOID)) %>%
    dplyr::inner_join(ct_pop, by = "GEOID") %>%
    dplyr::filter(lengths(st_intersects(., la_city)) > 0) %>%
    mutate(
      aland_km2   = ALAND / 1e6,
      pop_density = dplyr::if_else(aland_km2 > 0, estimate / aland_km2, NA_real_)
    ) %>%
    st_intersection(la_city) %>%
    dplyr::filter(!st_is_empty(.))

  make_box <- function(df, buf) {
    seed_buf <- df %>%
      dplyr::filter(!is.na(pop_density)) %>%
      dplyr::slice_max(pop_density, n = 1) %>%
      st_geometry() %>%
      st_centroid() %>%
      st_buffer(buf)
    center <- df %>%
      dplyr::filter(
        !is.na(pop_density),
        lengths(st_intersects(st_centroid(st_geometry(.)), seed_buf)) > 0
      ) %>%
      dplyr::slice_max(pop_density, n = 40) %>%
      st_union() %>%
      st_centroid()
    list(
      center = center,
      box    = st_buffer(center, buf) %>%
                 st_bbox() %>% st_as_sfc() %>% st_set_crs(proj_crs)
    )
  }

  boxes     <- vector("list", n)
  remaining <- ct_dens
  for (i in seq_len(n)) {
    r          <- make_box(remaining, buffer_sizes[i])
    boxes[[i]] <- r$box
    exclusion  <- st_buffer(r$center, min_separation_m)
    remaining  <- remaining %>%
      dplyr::filter(lengths(st_intersects(st_centroid(st_geometry(.)), exclusion)) == 0)
  }

  setNames(boxes, paste0("box", seq_len(n)))
}
