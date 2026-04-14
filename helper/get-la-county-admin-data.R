# FILE FOR PULLING VARIOUS LA COUNTY AND CITY ADMINISTRATIVE BOUNDARIES

# TODO: make it consistent whether or not it is transforming
library(tigris)
library(arcgislayers)
library(sf)
library(httr)
library(jsonlite)

get_from_url <- function(url) { 
  layer <- arc_open(url)
  boundary <- arc_select(layer)
  # check if valid
  valid <- st_is_valid(boundary)
  print(valid)
  
  if (any(!valid)) {
    # fix
    boundary <- st_make_valid(boundary)
  }
  
  return (boundary)
  
}

# la county boundary 
# last update: 08/03/2023
# source: https://egis-lacounty.hub.arcgis.com/datasets/0f58ddb711b84569ae0e7084c0404045_13/explore
get_county_boundary <- function() { 
  county_boundary_url <- "https://dpw.gis.lacounty.gov/dpw/rest/services/PW_Open_Data/MapServer/13"
  return(get_from_url(county_boundary_url))
}

# -------------------------------------------------------------------------------------------------
# Get LA City boundaries using census boundaries 
get_city_boundary <- function(proj_crs) { 
  city_boundary <- tigris::places(state="CA", class="sf", year=2022) %>%
    dplyr::filter(NAME == "Los Angeles") %>%
    st_transform(proj_crs) 
  
  return(city_boundary)
}

# ----------------------------------------- La county wide statistical areas --------------------------------------------------------

# Countywide statistical areas (CSAs)
# desc: Countywide statistical areas in Los Angeles County
# last update: 9/2016
# source: https://egis-lacounty.hub.arcgis.com/datasets/7b8a64cab4a44c0f86f12c909c5d7f1a_23/explore
# TODO download boundaries then write getter 

get_spa_boundaries <- function() { 
  spa_url <- "https://services.arcgis.com/RmCCgQtiZLDCtblq/arcgis/rest/services/Service_Planning_Areas_2022_view/FeatureServer/4/query?outFields=*&where=1%3D1"
  return (get_from_url(spa_url))
}

# ------------------------------------------ Land use and zoning -------------------------------------------------------
# desc: Land use and zoning map in Los Angeles County
# last update: 05/28/2021
# source: https://services1.arcgis.com/X1hcdGx5Fxqn4d0j/ArcGIS/rest/services/Land_Use_and_Zoning/FeatureServer/1

# TODO download boundaries then write getter 
get_openspace_parks <- function() { 
  landuse_url <- "https://services1.arcgis.com/X1hcdGx5Fxqn4d0j/ArcGIS/rest/services/Land_Use_and_Zoning/FeatureServer/1"
  landuse_boundary <- get_from_url(landuse_url)
}

get_zoning <- function() { 
  agri_url <- "https://services1.arcgis.com/X1hcdGx5Fxqn4d0j/ArcGIS/rest/services/Land_Use_and_Zoning/FeatureServer/3"
  agri_boundary <- get_from_url(agri_url)
}

# ------------------------------------------ LA county service planning areas (SPAs) -------------------------------------------------

# la county service planning areas
# desc: Service Planning Areas in Los Angeles County
# last update: 03/25/2022
# source: https://egis-lacounty.hub.arcgis.com/datasets/service-planning-areas-2022-view/explore

# ------------------------------------------ LA county cities -------------------------------------------------

# desc: Boundaries for the 88 cities and the unincorporated areas within Los Angeles County
# last update: 9/2016
# source: https://egis-lacounty.hub.arcgis.com/datasets/8ea349021cf544adb9bb079d3631df77_0/explore

# ------------------------------------------ LA city council districts 2021 -----------------------------------------------------

# LA city council districts 2021
# desc: Los Angeles City Council Districts, adopted in 2021
# last update: 12/20/2021
# source: https://geohub.lacity.org/datasets/76104f230e384f38871eb3c4782f903d

# ------------------------------------------ LA country census tracts --------------------------------------------------------

# LA country census tracts
# desc: Los Angeles County Census tracts 2020 boundaries with bodies of water removed
# source: 2020 Census TIGER/Line Shapefiles
# source: https://egis-lacounty.hub.arcgis.com/datasets/la-county-census-tracts-2020/explore
# land: if there is land (not a water CT)
download_census_tracts <- function(state="CA", county, year=2020, land=T) { 

  # do not remove bodies of water from census tracts for now since it will make geometries invalid
  all_tracts <- tigris::tracts(state=state, county=county, year = year, class="sf") #%>%
   # erase_water(year=2020)
  
  if(land==T) { 
    all_tracts <- all_tracts %>%
      filter(ALAND>0)
  }
  
  print(st_is_valid(all_tracts))
  
  # remove census tracts with no population
  st_write(all_tracts, paste0(base_path,  state,"_", county, "_", year,  "_census_tracts.gpkg"), append=F) 
  
}

# clip to some boundary
# example path
# /Users/angie/OneDrive/Desktop/data-analysis/0_shared-data/raw/CA_Los Angeles_2020_census_tracts.gpkg

get_census_tracts <- function(proj_crs, state, year, county, boundary=NULL) { 
  ct <- st_read(paste0(base_path, state,"_", county, "_", year,  "_census_tracts.gpkg")) %>%
    st_transform(proj_crs)
  
  
  if (!is.null(boundary)) {
    ct$indicator <- st_within(ct, boundary) %>%
      lengths > 0 
  
    ct <- ct %>% 
      filter(indicator == TRUE) %>%
      select(-indicator)
    
    print(head(ct))
    return(ct)
  }
  
  return(ct)
}

# ------------------------------------------ LA country census blocks -------------------------------------------
# desc: Los Angeles County Census blocks 2020 boundaries with bodies of water removed
# source: 2020 Census TIGER/Line Shapefiles

download_census_blocks <- function(state="CA", year=2020, county, land) { 
  # remove bodies of water from census tracts
  all_blocks <- tigris::blocks(state=state, county=county, year = year, class="sf") #%>%
    #erase_water(year=2020)
  
  if(land==T) { 
    all_blocks <- all_blocks %>%
      filter(ALAND20>0)
  }
  
  print(st_is_valid(all_blocks))
  
  st_write(all_blocks, paste0(base_path, state,"_", county, "_", year,  "_census_blocks.gpkg"), append=F) 
  
}

get_census_blocks <- function(proj_crs, state, year, county,boundary=NULL) { 
  cb <- st_read(paste0(base_path,  state,"_", county, "_", year, "_census_blocks.gpkg")) %>%
    st_transform(proj_crs)
  
  if (!is.null(boundary)) {
    cb$indicator <- st_within(cb, boundary) %>%
      lengths > 0 
    
    cb <- cb %>% 
      filter(indicator == TRUE) %>%
      select(-indicator)
  }
  
  cb
}

# ------------------------------------------ LA county households -------------------------------------------

# from: https://gis.stackexchange.com/questions/151613/reading-feature-class-in-file-geodatabase-using-r
download_lac_households <- function (proj_crs) { 
  
  unzip(paste0(base_path, "ParcelData_031325_LACountyParcelsAsHH_export.gdb.zip"), exdir = base_path)
  # The input file geodatabase
  
  # List all feature classes in a file geodatabase
  dsn = paste0(base_path, "ParcelData_031325_LACountyParcelsAsHH_export.gdb")
  fgdb <- st_layers(dsn) 

  print(fgdb)
  
  # Read the feature class
  fc <- st_read(dsn,layer="LACounty_Parcels_SpatialJoin_20_10_102424") %>%
    st_transform(proj_crs) %>%
    filter(is.na(EXCLUDE) & UseType=="Residential") %>% # IMPORTANT column "EXCLUDE" which is either null or "1" (~107 K) — if "1" we leave it out of our analyses because we don't want to include these units for various reasons.
    mutate(id=row_number()) %>%
    mutate(GEOID_20=as.character(GEOID_20)) 
  
  st_write(fc, dsn=paste0(processed_path, "LAC_origins/la_hh_cleaned.gdb"), append=F)
}

get_lac_households <- function(proj_crs) {
 la_hh <- st_read(paste0(processed_path, "LAC_origins/la_hh_cleaned.gdb")) |>
   st_transform(proj_crs) |>
   mutate(GEOID_20=paste0("0", as.character(GEOID_20)))
}

download_osm <- function(name="Southern California", location="socal", bbox) {
  # get road network data
  require(osmextract)
  
  # get best provider match for open street map data
  oe_get(name, boundary=bbox, download_directory=paste0(base_path,  "osm_", location), download_only=T)
}


# ------------------------------------------ Centroids and weighted centroids of census tracts
# PROCESSED DATA
get_lac_weight_centroids <- function() {
  return(st_read(paste0(processed_path, "LAC_origins/la_ct_wtcent_dat3182025.gpkg")))
}

get_lac_centroids <- function() {
  return(st_read(paste0(processed_path, "LAC_origins/la_ctcent_dat3182025.gpkg")))
}

# ------------------------------------------ Road network data

get_osm <- function(location="socal", bbox) {
  # get road network data
  require(osmextract)
  pbf_file <- paste0(base_path, "osm_", location, "/geofabrik_", location, "-latest.osm.pbf")  # Path to your downloaded PBF file
  gpkg_file <- paste0(base_path,  "osm_", location, "/geofabrik_",  location, "-latest.osm.gpkg")  # Path to your downloaded GPKG file
  # if no gpkg file exists, read pbf
  if (!file.exists(gpkg_file)) {
    osm_lines <- oe_read(pbf_file, provider="geofabrik", boundary=bbox)  # Change layer to "points", "polygons" as needed
 
  } else {
    osm_lines <- oe_read(gpkg_file, provider="geofabrik", boundary=bbox)  # Change layer to "points", "polygons" as needed
  }
  
  return(osm_lines)

}

# ------------------------------------------ Elevation data 

download_dem <- function(boundary, location="socal") { 
  # download dem data
  require(elevatr)
  require(terra)
  dem <- get_elev_raster(boundary, z=10)
  terra::writeRaster(dem, paste0(base_path,  "osm_", location, "/", location, "_dem.tif"))
}

get_dem <- function(location="socal", proj_crs) { 
  # get dem data
  require(terra)
  dem <- terra::rast(paste0(base_path, "osm_", location, "/", location, "_dem.tif"))
  crs <- paste0("EPSG:",proj_crs)
  dem <- project(dem, crs)  # Convert to WGS 84 if necessary

  return(dem)
}

