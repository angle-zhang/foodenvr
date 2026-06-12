source('./0_Libraries.R')

<<<<<<< HEAD
# ------ LOAD BOUNDARIES AND CRS ------ #
=======
# =============================================================================
# PAPER SECTION A: DATA COLLECTION
# Downloads all raw input data required for the food environment workflow:
#   - Spatial boundaries (census tracts, census blocks)
#   - Elevation data (DEM via elevatr)
#   - Street network (OSM via osmextract)
#   - Food POI: Data Axle (proprietary) or SNAP retailers (public alternative)
#   - Health outcome data (CDC PLACES)
# =============================================================================

download_foodins_lacounty_ssi()
download_census_tracts(state="CA", county="Los Angeles", year=2020, land=T)
download_census_blocks(state="CA", county="Los Angeles", year=2020, land=T)

# write.csv(la_hh_temp, paste0(processed_path, "/LAC_origins/la_hh_cleaned.csv"))

# ------ LOAD BOUNDARIES AND CRS (Section A: Spatial boundaries) ------ #
# TODO get edges outside LA County
# get suggested CRS
>>>>>>> a3165853c49db09c47459ba08a0d3666c588d5e9

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

<<<<<<< HEAD
# ------ DOWNLOAD ELEVATION AND STREETMAP DATA + CLIP TO BUFFER ------ #

download_dem(path=base_path, boundary=lac_buffer, county=proj_county)
download_osm(place_name="Southern California", bbox=lac_bbox, county=proj_county)
=======
# ------ DOWNLOAD ELEVATION AND STREET NETWORK DATA (Section A: Elevation + Street network) ------ #
download_dem(lac_buffer, "socal")
download_osm(bbox=lac_bbox)

# =============================================================================
# PAPER SECTION B: DATA CLEANING - POPULATION POINTS
# Three population representation methods:
#   1. Census tract centroids
#   2. Population-weighted census tract centroids (using 2020 census block counts)
#   3. Households from parcel data (processed separately via download_lac_households())
# =============================================================================

# ------ GET CENTROIDS OF CTs ------ #
# gets centroid of census blocks then calculates the population weighted centroid of a census tract based on those
# for centroids that lie outside a census block, st_point_on_surface is used to get a point within the polygon
la_ctcent <- calc_pop_weighted_centroid(la_cb, 'TRACTCE20', 'POP20') %>% 
  st_transform(proj_crs)
>>>>>>> a3165853c49db09c47459ba08a0d3666c588d5e9

# ------ DOWNLOAD CENSUS TRACT DATA FROM APIS ------ #

download_census_tracts(state=proj_state, county=proj_county, year=proj_year, land=T)
download_census_blocks(state=proj_state, county=proj_county, year=proj_year, land=T)

save_naics(processed_path)

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

<<<<<<< HEAD
# ------ LOAD SNAP POI DATA ------ #
# TODO make this part of API
# Load SNAP historical data for the year 2021
=======
# ------ LOAD SNAP POI DATA (Section A: public food POI alternative) ------ #
# SNAP retailer data is a publicly available alternative to proprietary Data Axle POI.
# Download and load SNAP retailer data for use as the food POI input when Data Axle is unavailable.
# download_snap_historical()  # run once to download
>>>>>>> a3165853c49db09c47459ba08a0d3666c588d5e9
# snap_historical <- get_snap_historical(years = 2021, proj_crs = st_crs(lac_boundary))
# snap_current <- get_snap_current(polygon = lac_buffer, proj_crs = proj_crs)


# sample_food <- foodinsp23_24_SSI[sample(nrow(foodinsp23_24_SSI), 300), ] 
# st_write(sample_food, "../data/sample-poi/sample_poi.gpkg", append=F)

# Display unique 'USER_PE_DESCRIPTION' values
# unique_descriptions <- unique(foodinsp23_24_SSI$source)
# 
# print(names(foodinsp23_24_SSI))
# print(unique_descriptions)

<<<<<<< HEAD
# ------ HEALTH OUTCOME DATA ------ #
# # ------ DOWNLOAD LA COUNTY FOOD INSPECTION DATA ----- #
# download_foodins_lacounty_ssi()
# save_data_axle(year=proj_year, state=proj_state) # from zipped file
=======

# ------ HEALTH OUTCOME DATA (Section A: health outcomes) ------ #
CDCPlaces_dict <- get_CDCPlaces_dict()
places_vars <- get_CDCPlaces(geography='census', measure=c("DIABETES", "OBESITY", "FOODSTAMP", "FOODINSECU", "HOUSINSECU"), state="CA", geometry=T, release='2024') %>%
  filter(countyname == 'Los Angeles')

unique(places_vars$countyname)
>>>>>>> a3165853c49db09c47459ba08a0d3666c588d5e9

