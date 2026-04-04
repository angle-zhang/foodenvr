source('./0_Libraries.R')

download_foodins_lacounty_ssi()
download_census_tracts(state="CA", county="Los Angeles", year=2020, land=T)
download_census_blocks(state="CA", county="Los Angeles", year=2020, land=T)

# write.csv(la_hh_temp, paste0(processed_path, "/LAC_origins/la_hh_cleaned.csv"))

# ------ LOAD BOUNDARIES AND CRS ------ #
# TODO get edges outside LA County
# get suggested CRS

# convert to suggested crs
lac_boundary <- st_transform(get_county_boundary(), proj_crs)
st_crs(lac_boundary, parameters = TRUE)$units_gdal # check units

lac_buffer <- st_buffer(lac_boundary, 5280*15) # get buffer in 15 mile zone
lac_bbox <- lac_buffer %>% st_transform(4326) %>% st_bbox()
print(lac_bbox)
#la_hh <- get_lac_households(proj_crs)
## clip to boundary, right now buffer area not needed 
la_ct <- get_census_tracts(proj_crs, state="CA", year=2020, county="Los Angeles")
la_cb <- get_census_blocks(proj_crs, state="CA", year=2020, county="Los Angeles")

# get geometry type of la_cb
print(unique(st_geometry_type(la_cb)))
unique(st_is_valid(la_cb, reason=T))

# DOWNLOAD DATA
download_dem(lac_buffer, "socal")
download_osm(bbox=lac_bbox)

# ------ GET CENTROIDS OF CTs ------ #
# gets centroid of census blocks then calculates the population weighted centroid of a census tract based on those
# for centroids that lie outside a census block, st_point_on_surface is used to get a point within the polygon
la_ctcent <- calc_pop_weighted_centroid(la_cb, 'TRACTCE20', 'POP20') %>% 
  st_transform(proj_crs)

# merge ct weighted centroids with rest of census tract data
# remove empty geometries
la_ct_wtcent_dat <- la_ct %>%
  st_drop_geometry() %>%
  left_join(la_ctcent, by=c('TRACTCE'='TRACTCE20')) %>%
  st_as_sf() %>%
  filter(!st_is_empty(.)) # remove empty points due to CBs with no population

# get unweighted centroids of census tracts
la_ctcent_dat <- la_ct %>%
  st_centroid() %>%
  st_transform(proj_crs)

write_sf(la_ct_wtcent_dat, paste0(processed_path, "LAC_origins/la_ct_wtcent_dat3182025.gpkg"))
write_sf(la_ctcent_dat, paste0(processed_path, "LAC_origins/la_ctcent_dat3182025.gpkg"))

la_ct_wtcent_dat <- get_lac_weight_centroids()
la_ctcent_dat <- get_lac_centroids()

# rm(la_ctcent_dat, la_ct_wtcent_dat, la_ctcent, la_ct, la_cb)
# unique(st_geometry_type(la_ctcent_dat))
# st_crs(la_ctcent_dat)

# get sample for mapping
la_hh_sample <- la_hh_cleaned[sample(nrow(la_hh_cleaned), 500), ]

# ------ LOAD SNAP POI DATA ------ #
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
CDCPlaces_dict <- get_CDCPlaces_dict()
places_vars <- get_CDCPlaces(geography='census', measure=c("DIABETES", "OBESITY", "FOODSTAMP", "FOODINSECU", "HOUSINSECU"), state="CA", geometry=T, release='2024') %>%
  filter(countyname == 'Los Angeles') 

unique(places_vars$countyname)

