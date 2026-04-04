calc_pop_weighted_centroid <- function(geo_data, group_col, weight_col) {
  # get centroid of blocks and remove empty geometries
  res <<- geo_data %>%
    subset(!st_is_empty(.)) %>%
    st_make_valid() %>%
    st_centroid_within_poly() %>% # get the centroid within the block first 
    mean_center(group=group_col, weight=weight_col)
  
  geom_col_name <- attr(res, "sf_column")
  
  if(geom_col_name == "geom") res <- res |> rename(geometry=geom)
  
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

clipintersect_boundary <- function(result, boundary) { 
  # create slight buffer
  boundary1 <- st_buffer(boundary, 0) 
  
  result$indicator <- result %>%
    st_intersects(boundary1) %>% 
    lengths > 0
  
  result1 <- result %>%
    filter(indicator) %>%
    select(-indicator)
  
  return(result1)
}
