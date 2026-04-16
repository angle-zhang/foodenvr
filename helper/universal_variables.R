
# helper/universal_variables.R
# TODO eventually workflow should work with these variables and the data provided to run each script sequentially 
# without intervention
proj_year        <- 2022
proj_state       <- "CA"
proj_county      <- "Los Angeles"
proj_crs <- as.integer(suggest_crs(get_county_boundary())$crs_code[1])
proj_coord_crs <- 4326

st_crs(proj_crs)$units

# MAKE SURE ITS IN SAME UNITS AS PROJ_CRS
proj_buffer_size <- 5280 * 30 # 30 miles in feet



