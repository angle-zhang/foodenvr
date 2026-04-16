source('./0_Libraries.R')

# ------ LOAD BOUNDARIES AND CRS ------ #

# convert to suggested crs
lac_boundary <- st_transform(get_county_boundary(), proj_crs)
# st_crs(lac_boundary, parameters = TRUE)$units_gdal # check units

lac_buffer <- st_buffer(lac_boundary, proj_buffer_size) # get buffer in proj_buffer_size mile zone
lac_bbox <- lac_buffer %>% st_transform(proj_coord_crs) %>% st_bbox() # create a bbox from buffer 

# inspect: map buffer and bbox 
# tm_shape(lac_buffer)  + 
#   tm_polygons(col="blue") + 
#   tm_shape(lac_boundary) + 
#   tm_polygons(col="green") #+ 
#   tm_shape(lac_bbox) + 
#   tm_polygons(col="red")

# ------ DOWNLOAD ELEVATION AND STREETMAP DATA + CLIP TO BUFFER ------ #

download_dem(path=base_path, boundary=lac_buffer, county=proj_county)
download_osm(place_name="Southern California", bbox=lac_bbox, county=proj_county)

# ------ DOWNLOAD CENSUS TRACT DATA FROM APIS ------ #

download_census_tracts(state=proj_state, county=proj_county, year=proj_year, land=T)
download_census_blocks(state=proj_state, county=proj_county, year=proj_year, land=T)

# write.csv(la_hh_temp, paste0(processed_path, "/LAC_origins/la_hh_cleaned.csv"))

# inspect: map centroid points
# tm_shape(lac_boundary)  +
#   tm_polygons(col="blue") +
#   tm_shape(la_ct_wtcent_dat) +
#   tm_dots(col="green") +
#   tm_shape(la_ctcent_dat) +
#   tm_dots(col="red")

# # ------ DOWNLOAD LA COUNTY FOOD INSPECTION DATA ----- #
# download_foodins_lacounty_ssi()
# save_data_axle(year=proj_year, state=proj_state) # from zipped file

# rm(la_ctcent_dat, la_ct_wtcent_dat, la_ctcent, la_ct, la_cb)
# unique(st_geometry_type(la_ctcent_dat))
# st_crs(la_ctcent_dat)

# get sample for mapping
# la_hh_sample <- la_hh_cleaned[sample(nrow(la_hh_cleaned), 500), ]

# ------ LOAD SNAP POI DATA ------ #
# TODO make this part of API
# Load SNAP historical data for the year 2021
# snap_historical <- get_snap_historical(years = 2021, proj_crs = st_crs(lac_boundary))


# sample_food <- foodinsp23_24_SSI[sample(nrow(foodinsp23_24_SSI), 300), ] 
# st_write(sample_food, "../data/sample-poi/sample_poi.gpkg", append=F)

# Display unique 'USER_PE_DESCRIPTION' values
# unique_descriptions <- unique(foodinsp23_24_SSI$source)
# 
# print(names(foodinsp23_24_SSI))
# print(unique_descriptions)

# ------ HEALTH OUTCOME DATA ------ #
# # ------ DOWNLOAD LA COUNTY FOOD INSPECTION DATA ----- #
# download_foodins_lacounty_ssi()
# save_data_axle(year=proj_year, state=proj_state) # from zipped file

