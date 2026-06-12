# =============================================================================
# PAPER SECTION D: SUMMARIZING DATA AT DIFFERENT SPATIAL SCALES
# Merges chunked accessibility output files, aggregates parcel-level measures
# to the census tract level, and merges all population representation methods
# into a single wide-format dataset for comparison.
#
# Also computes ratio measures (Paper Section C):
#   - Supermarket Ratio = SMK / total food POI (CNV + FF + GRC + RR + SMK + SPF)
#   - Fast Food Ratio  = FF / (FF + RR)
# =============================================================================

source("0_Libraries.R")
source("./helper/gen-helper.R")

library(tidytable)

# Pull in census tract and household geographic data  -------------------------------
la_ct <- get_census_tracts(crs=proj_crs, state=proj_state, year=proj_year, county=proj_county)
la_hh <- get_lac_households(processed_path, proj_coord_crs)
la_city <- get_city_boundary(proj_crs)

la_city_ct <- la_ct %>%
  dplyr::filter((lengths(st_intersects(., la_city)) > 0)) %>%
  st_transform(proj_coord_crs)

temp <- head(la_hh, 10000)
# include households with census tract in la city
la_city_hh <- la_hh %>%
  filter(GEOID_20 %in% la_city_ct$GEOID) 

# get census tracts key for GEOID
la_ct_key <- read_csv(paste0(processed_path, "/LAC_origins/la_ct_key.csv")) |>
  select(-...1)

density_path <- paste0(access_path, "/density/la_city/CATG")

#'* Pull, merge, and process files ----------- *
dt_ct_cent <- get_and_merge_files(density_path, "ct_cent_CAR")
dt_ct_cent1 <- dt_ct_cent |>
  calc_relative_measures()

dt_ct_wtcent <- get_and_merge_files(density_path, "ct_wtcent_CAR")
dt_ct_wtcent1 <- dt_ct_wtcent |>
  calc_relative_measures()

dt_household <- get_and_merge_files(density_path, "parcel_CAR")
dt_household1 <- dt_household |>
  calc_relative_measures()

# convert to wide with opportunity and cutoff merged as column name and accessibility as value
dt_household_ct <- process_times(dt_household1 |> select(-row.names), la_city_hh %>% st_drop_geometry(), GEOID="GEOID_20",
                                            agg=TRUE, scale="parcel", type="driving")
head(dt_household_ct)
# join ct data with driving times
dt_ct_centm <- process_times(dt_ct_cent1 |> select(-row.names), la_ct_key, type="driving", scale="ct_cent", agg=F)
dt_ct_wtcentm <- process_times(dt_ct_wtcent1 |> select(-row.names), la_ct_key, type="driving", scale="ct_wtcent", agg=F)


# write aggregated parcel data 
data.table::fwrite(dt_household_ct, paste0(processed_path, "LAC_cleaned/dt_household_ct.csv"))


#'* dt_household = household level food environment measures *
#'* dt_household_ct = household level food environment measures aggregated to the census tract level*
# temp <- dt_household %>% filter(is.na(id))
# temp <- head(dt_household_ct, 2000)

# TODO 12/19/2025 get parcel means (not aggregated) -------------------------------
# get geoids in la_hh
la_city_GEOID <- la_city_hh %>%
  st_drop_geometry() %>%
  select(GEOID_20) %>%
  unique() 

#'* pull USDA food access measures for comparison*
usdafa <- openxlsx::read.xlsx(paste0(base_path, "./USDA_foodatlas/FoodAccessResearchAtlasData2019.xlsx"), sheet=3) 
usdafa_la <- usdafa |> 
  mutate(GEOID=as.character(CensusTract)) |> 
  filter(GEOID %in% la_city_GEOID$GEOID_20) |>
  select(GEOID, starts_with("LA1"), LAhalfand10, starts_with("LAT")) 
  
#'* DO NOT ALTER: Merge all census-tract level data including aggregate parcel level data* -------------------------------
# driving times (ct_cent, ct_wtcent, household) by geoid

ct_driving <- dt_ct_centm %>%
  select(-id) %>%
  left_join(dt_ct_wtcentm, by = "GEOID") %>%
  left_join(dt_household_ct, by ="GEOID") %>%
  select(-id) %>%
  pivot_longer(!GEOID, names_to="features", values_to="count") %>%
  tidyr::separate_wider_delim(features, delim="_", names=c("network", "type", "drive", "pop_rep"), too_many="merge", too_few="align_start") |>
  pivot_wider(names_from=pop_rep, values_from=count) |>
  left_join(usdafa_la, by="GEOID") %>%
  filter(GEOID %in% la_city_GEOID$GEOID_20) 

write_csv(ct_driving, paste0(processed_path, "LAC_cleaned/ct_driving_times.csv"))
rm(ct_driving, ct_driving_ratio, usdafa, usdafa_la)

#'* Process household/parcel-level data (non-aggregate) * -------------------------------
parcel_driving1 <- dt_household1 |>
  process_times(la_city_hh, GEOID="GEOID_20",
                agg=FALSE, scale="parcel", type="driving") |>
  mutate(GEOID=ifelse(GEOID=="06037980022","06037106645",GEOID)) # manual workaround for CT that was mis-geocoded 

parcel_drivingdt <- as.data.table(parcel_driving1) |>
  melt(id.vars = c("GEOID", "id"),
       variable.name = "features",
       value.name = "count") |>
  tidytable::separate_wider_delim(features, delim="_", names=c("network", "type", "drive", "pop_rep"), too_many="merge", too_few="align_start") |>
  drop_na(count)

# write household data csv with household data ONLY
data.table::fwrite(parcel_drivingdt, paste0(processed_path, "LAC_cleaned/parcel_drivingdt.csv"))

# merge census data into household-level data
parcel_driving_all <- parcel_drivingdt |> 
  tidytable::left_join(ct_driving, by=c("GEOID", "type", "drive", "network")) 

data.table::fwrite(parcel_driving_all, paste0(processed_path, "LAC_cleaned/parcel_driving_all.csv"))


  

