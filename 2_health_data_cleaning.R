source("./0_Libraries.R")
source("./helper/gen-helper.R")

library(openxlsx)
library(stringr)
# ------------------ pulling geocoded data ------------------
# TODO 
# - (DONE) Verify these files are correct ones payal was referring to
# - Test association between household-level measures, census tract level, and zip-code measures (DO LATER) in participant population; 
  # merge geocodes and participant BMI/CDE data 
  # merge all participant data (p1...p4)

geocoding_path <- "../../0_shared-data/latino-health-elsendero/raw/Geocoding/Complete/"
p1mm_geodata <- read.xlsx(paste0(geocoding_path, "MothersMilk (Batch 3 Final Geocoding with All Edits 25NOV_HL.xlsx).xlsx")) %>%
  filter(!is.na(NewLatitude)) |>
  st_as_sf(coords=c("NewLongitude","NewLatitude")) |>
  mutate(mergeID = row_number()) |> 
  mutate(visit_date = as.Date(as.numeric(visit_date), origin = "1899-12-30")) |> 
  mutate(baby_dob = as.Date(as.numeric(baby_dob), origin = "1899-12-30"))

# TODO ask payal why P1 and P2 organized differently? oes P1 and P2 have DOV and DOB data? 


#'* DOB enrichment and DOV enrichment sheets *
# TODO decide if using DOB or DOV
# TODO decide if using child observation (if so we want to use DOB as well as DOV)
p2_geodataDOB <- read.xlsx(paste0(geocoding_path, "NIMHDP50MasterProjec-Project2ResidentialH_DATA_2025-06-06_Enriched_0925_SSI.xlsx"), sheet="DOB_Enrichment_SSI_P2") %>%
  filter(!is.na(X)) |>
  st_as_sf(coords=c("X", "Y"))|>
  mutate(mergeID = nrow(p1mm_geodata) + row_number())

p2_geodataDOV <- read.xlsx(paste0(geocoding_path, "NIMHDP50MasterProjec-Project2ResidentialH_DATA_2025-06-06_Enriched_0925_SSI.xlsx"), sheet="DOV_Enrichment_SSI_P2") %>%
  filter(!is.na(X)) |>
  st_as_sf(coords=c("X", "Y")) |>
  mutate(mergeID = nrow(p1mm_geodata) + nrow(p2_geodataDOB) + row_number())

# TODO get list of all (coord) geometries to run gen_measures code on
# TODO need to do same with GEOIDs

combined_geo <- p1mm_geodata |> select(mergeID, geometry) |>
  rbind(p2_geodataDOB |> select(mergeID, geometry)) |>
  rbind(p2_geodataDOV |> select(mergeID, geometry)) |> 
  st_set_crs(4326) 

xy  <- st_coordinates(combined_geo)
lon <- xy[, 1]
lat <- xy[, 2]
# Get 

indiv_geo <- combined_geo

indiv_geo$indiv_cb <- mapply(
  FUN = function(lon_i, lat_i) {
    tryCatch(
      call_geolocator_latlon(lon = lon_i, lat = lat_i),
      error = function(e) NA_character_
    )
  },
  lon, lat,
  USE.NAMES = FALSE
) 

rm(xy, lon, lat)

indiv_geo$GEOID <- str_sub(indiv_geo$indiv_cb, 1,11) 

indiv_geo$state <- str_sub(indiv_geo$GEOID, 1, 2)
indiv_geo$county <- str_sub(indiv_geo$GEOID, 3, 5)

# deal with 3 missing values in indiv_geo
stateco_pairs <- indiv_geo |> 
  distinct(state, county) |>
  filter(!is.na(state))

tracts_sf <- pmap_dfr(
  stateco_pairs,
  function(statefp, countyfp) {
    tigris::tracts(state = statefp, county = countyfp, year = 2022, cb = TRUE, class="sf")  
  }
) 

indiv_ct <- indiv_geo |>
  st_drop_geometry() |>
  left_join(tracts_sf, by= c("GEOID"="GEOID")) |> 
  st_as_sf() # detect crs of census data

# get the centroid of each census tract
indiv_ctcent <- indiv_ct %>%
  st_centroid() |> 
  st_transform(4326) 

# unique values only to be mapped to indiv_ctcent
# id column is needed for use with r5r (id=geoid)
indiv_ctcent_u <- indiv_ctcent |> 
  select(GEOID) |> 
  unique() |> 
  rename(id=GEOID)
  
# get weighted centroid
blocks_sf <- pmap_dfr(
  stateco_pairs,
  function(statefp, countyfp) {
    tigris::blocks(state = statefp, county = countyfp, year = 2022, class="sf")  
  }
)

# only get blocks in the individual scclh dataset
indiv_blocks <- indiv_geo |>
  st_drop_geometry() |>
  left_join(blocks_sf, by= c("indiv_cb"="GEOID20")) |> 
  st_as_sf() 

# TODO handle case where individual lives in census block with zero population...
# get weighted centroids
indiv_ct_wtcent <- calc_pop_weighted_centroid(indiv_blocks, 'TRACTCE20', 'POP20') |> 
  left_join(indiv_blocks |> st_drop_geometry(), by="TRACTCE20") |>
  st_transform(4326) 


indiv_ct_wtcent_u <- indiv_ct_wtcent |> 
  select(GEOID) |> 
  unique() |> 
  rename(id=GEOID)

# --------- map geoids / centroid points to ensure they are properly selected ----
# get county boundary and water
la_county <- get_county_boundary() %>%
  st_transform(proj_crs)

la_city <- get_city_boundary(proj_crs) %>%
  st_transform(proj_crs)

tm_shape(la_county) +
  tm_borders() +
  tm_shape(indiv_ct_wtcent) +
  tm_dots() +
  tm_shape(indiv_ctcent) +
  tm_dots(col="red") 

# ------------------ Calculating FE measures for geocoded data ------------------
st_crs(foodpoi) == st_crs(indiv_ct_wtcent_u)
st_crs(foodpoi) == st_crs(indiv_ctcent_u)

# TODO for addresses outside of california, do not take into account? or calculate measures for those areas as well
access_CAR <- compute_accessibility(
  origins = indiv_ct_wtcent_u,
  destinations = foodpoi,
  cutoffs = c(5, 10, 15, 20, 25, 30),
  mode = "CAR",
  chunk_size = 8, #calc_chunk_size(ram=6, mode="CAR"),  #calc_chunk_size(ram=12, mode="WALK"),
  output_path = paste(access_path, "density/la_city/CATG/", sep="/"),
  origin_type = "ct_wtcent_CAR_LHdata",
  colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
  #file_id="CAT"
)

access_CAR <- compute_accessibility(
  origins = indiv_ctcent_u,
  destinations = foodpoi,
  cutoffs = c(5, 10, 15, 20, 25, 30),
  mode = "CAR",
  chunk_size = 5, #calc_chunk_size(ram=6, mode="CAR"),  #calc_chunk_size(ram=12, mode="WALK"),
  output_path = paste(access_path, "density/la_city/CATG/", sep="/"),
  origin_type = "ct_cent_CAR_LHdata",
  colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
  #file_id="CAT"
)

# Check that origins and destinations are same crs
st_crs(foodpoi) == st_crs(combined_geo)

access_CAR <- compute_accessibility(
  origins = combined_geo,
  destinations = foodpoi,
  cutoffs = c(5, 10, 15, 20, 25, 30),
  mode = "CAR",
  chunk_size = 5, #calc_chunk_size(ram=6, mode="CAR"),  #calc_chunk_size(ram=12, mode="WALK"),
  output_path = paste(access_path, "density/la_city/CATG/", sep="/"),
  origin_type = "address_LHdata",
  colnames = c("CNV", "FF", "GRC", "Not.included", "RR", "SMK", "SPF")
  #file_id="CAT"
)

# Calculate measures from data and perform merge
density_path <- paste0(access_path, "/density/la_city/CATG")

dt_ct_cent <- get_and_merge_files(density_path, "ct_cent_CAR_LHdata")
dt_ct_wtcent <- get_and_merge_files(density_path, "ct_wtcent_CAR_LHdata")
dt_household <- get_and_merge_files(density_path, "address_LHdata") 

# convert to wide with opportunity and cutoff merged as column name and accessibility as value
dt_household_ctm <- process_times(dt_household |> select(-row.names), la_city_hh %>% st_drop_geometry(), GEOID="GEOID_20", 
                                 agg=TRUE, scale="parcel", type="driving")
head(dt_household_ct)

dt_householdm <- dt_household |> process_times(la_city_hh, GEOID="GEOID_20",
                agg=FALSE, scale="parcel", type="driving") |> 
  mutate(GEOID=ifelse(GEOID==6037980022,6037106645,GEOID))

# join ct data with driving times
dt_ct_centm <- process_times(dt_ct_cent |> select(-row.names), la_ct_key, type="driving", scale="ct_cent", agg=F)
dt_ct_wtcentm <- process_times(dt_ct_wtcent |> select(-row.names), la_ct_key, type="driving", scale="ct_wtcent", agg=F)


# ------------------ pulling health data ------------------
health_path <- "../../0_shared-data/latino-health-elsendero/raw/BMI tables/Parent BMI/"

p1_hdata <- fread(paste0(health_path, "P50-P1-Parent-Common Data Elements-Organized & Complete.csv"))
p2_hdata <- fread(paste0(health_path, "P50-P3-Parent-Common Data Elements-Organized & Complete.csv"))

combined_hdata <- p1_hdata %>% rbind(p2_hdata)
# p1_hdata <- 
# p2_hdata <- 

# TODO analysis file (make new file)
# P-values comparing quintiles of each geographic level (example- see methods)

# Testing association between food environment and perceived? and BMI? 