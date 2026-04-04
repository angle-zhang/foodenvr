
# Section A: Data collection
# Downloads all required inputs for the food environment analysis:
#   - Food retail POI (SSI food inspection data; substitute for proprietary Data Axle POI)
#   - Census spatial boundaries (tracts and blocks via tigris)
#   - Elevation data (DEM via elevatr / Open Topography API)
#   - Street network (OSM via osmextract)
#   - Health outcome data (CDC PLACES)
# NOTE: Parcel/cadastral data (Section B, population points) must be supplied by the user.
#       See get_lac_households() in helper/get-la-county-admin-data.R.

source('./0_Libraries.R')

# ------ FOOD RETAIL POI ------ #
# Download food retail point-of-interest data from SSI food inspection services
# Proprietary Data Axle POI can be substituted here; see get_data_axle() in helper/get-food-data.R
download_foodins_lacounty_ssi()

# ------ SPATIAL BOUNDARIES ------ #
# Download 2020 census tract and block boundaries for LA County (land areas only)
download_census_tracts(state="CA", county="Los Angeles", year=2020, land=T)
download_census_blocks(state="CA", county="Los Angeles", year=2020, land=T)

# ------ LOAD BOUNDARIES AND CRS ------ #
# Convert to projected CRS and create a 15-mile buffer for network/elevation downloads
lac_boundary <- st_transform(get_county_boundary(), proj_crs)
st_crs(lac_boundary, parameters = TRUE)$units_gdal # check units

lac_buffer <- st_buffer(lac_boundary, 5280*15) # get buffer in 15 mile zone
lac_bbox <- lac_buffer %>% st_transform(4326) %>% st_bbox()
print(lac_bbox)

la_ct <- get_census_tracts(proj_crs, state="CA", year=2020, county="Los Angeles")
la_cb <- get_census_blocks(proj_crs, state="CA", year=2020, county="Los Angeles")

# get geometry type of la_cb
print(unique(st_geometry_type(la_cb)))
unique(st_is_valid(la_cb, reason=T))

# ------ ELEVATION AND STREET NETWORK ------ #
# Download digital elevation model (DEM) and OpenStreetMap (OSM) street network
# These are used in Section C when setting up the r5r routing engine
download_dem(lac_buffer, "socal")
download_osm(bbox=lac_bbox)

# ------ LOAD SNAP POI DATA ------ #
# Load SNAP historical data for the year 2021 (optional; substitute for proprietary POI)
# snap_historical <- get_snap_historical(years = 2021, proj_crs = st_crs(lac_boundary))

# ------ HEALTH OUTCOME DATA ------ #
# Download census-tract level health outcomes from CDC PLACES (2024 release)
CDCPlaces_dict <- get_CDCPlaces_dict()
places_vars <- get_CDCPlaces(geography='census', measure=c("DIABETES", "OBESITY", "FOODSTAMP", "FOODINSECU", "HOUSINSECU"), state="CA", geometry=T, release='2024') %>%
  filter(countyname == 'Los Angeles') 

unique(places_vars$countyname)

