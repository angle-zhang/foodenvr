source("0_Libraries.R")
source("./helper/gen-helper.R")

library(tidytable)

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

#TODO untransform GEOIDs from as.numeric

# Pull in census tract and household geographic data  -------------------------------
la_ct <- get_census_tracts(proj_crs, state="CA", year=2020, county="Los Angeles")
la_hh <- get_lac_households(4326)
la_city <- get_city_boundary(proj_crs)
tm_shape(la_city) + tm_borders() # inspect city

head(la_hh)

la_city_ct <- la_ct %>%
  dplyr::filter((lengths(st_intersects(., la_city)) > 0)) %>%
  st_transform(4326)

# include households with census tract in la city
# TODO la_city_hh geoid_20 is in numeric format; must correct
la_city_hh <- la_hh %>%
  filter(GEOID_20 %in% la_city_ct$GEOID) 

# get census tracts key for GEOID
la_ct_key <- read.csv(paste0(processed_path, "/LAC_origins/la_ct_key.csv")) %>%
  select(-X)

density_path <- paste0(access_path, "/density/la_city/CATG")


#'* Pull, merge, and process files ----------- *
dt_ct_cent <- get_and_merge_files(density_path, "ct_cent_CAR")
dt_ct_wtcent <- get_and_merge_files(density_path, "ct_wtcent_CAR")
dt_household <- get_and_merge_files(density_path, "parcel_CAR") 
head(dt_household)

# inspect
# sample <- sample(nrow(dt_household), 500)
# dt_household <- dt_household[sample,]
# temp <- dt_household
# head(dt_household)
# head(la_city_hh)

# convert to wide with opportunity and cutoff merged as column name and accessibility as value
dt_household_ct <- process_times(dt_household |> select(-row.names), la_city_hh %>% st_drop_geometry(), GEOID="GEOID_20", 
                                            agg=TRUE, scale="parcel", type="driving")
head(dt_household_ct)
# join ct data with driving times
dt_ct_centm <- process_times(dt_ct_cent |> select(-row.names), la_ct_key, type="driving", scale="ct_cent", agg=F)
dt_ct_wtcentm <- process_times(dt_ct_wtcent |> select(-row.names), la_ct_key, type="driving", scale="ct_wtcent", agg=F)


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
  
unique(usdafa$CensusTract)

#'* DO NOT ALTER: Merge all census-tract level data including aggregate parcel level data* -------------------------------
# TODO add in USDA data
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

#'* Compute ratio measures (Paper Section C) *
# Supermarket Ratio = SMK / total food POI within buffer
# Fast Food Ratio   = FF  / (FF + RR) within buffer
# Total food POI excludes "Not.included" category

food_types_all <- c("CNV", "FF", "GRC", "RR", "SMK", "SPF")

ct_driving_ratio <- ct_driving %>%
  filter(type %in% food_types_all) %>%
  select(GEOID, network, type, drive, ct_cent, ct_wtcent, parcel_mean) %>%
  group_by(GEOID, network, drive) %>%
  summarise(
    total_ct_cent    = sum(ct_cent,    na.rm = TRUE),
    total_ct_wtcent  = sum(ct_wtcent,  na.rm = TRUE),
    total_parcel_mean = sum(parcel_mean, na.rm = TRUE),
    smk_ct_cent      = sum(ct_cent[type == "SMK"],    na.rm = TRUE),
    smk_ct_wtcent    = sum(ct_wtcent[type == "SMK"],  na.rm = TRUE),
    smk_parcel_mean  = sum(parcel_mean[type == "SMK"], na.rm = TRUE),
    ff_ct_cent       = sum(ct_cent[type == "FF"],    na.rm = TRUE),
    ff_ct_wtcent     = sum(ct_wtcent[type == "FF"],  na.rm = TRUE),
    ff_parcel_mean   = sum(parcel_mean[type == "FF"], na.rm = TRUE),
    rr_ct_cent       = sum(ct_cent[type == "RR"],    na.rm = TRUE),
    rr_ct_wtcent     = sum(ct_wtcent[type == "RR"],  na.rm = TRUE),
    rr_parcel_mean   = sum(parcel_mean[type == "RR"], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    smk_ratio_ct_cent    = smk_ct_cent    / total_ct_cent,
    smk_ratio_ct_wtcent  = smk_ct_wtcent  / total_ct_wtcent,
    smk_ratio_parcel_mean = smk_parcel_mean / total_parcel_mean,
    ff_ratio_ct_cent     = ff_ct_cent     / (ff_ct_cent    + rr_ct_cent),
    ff_ratio_ct_wtcent   = ff_ct_wtcent   / (ff_ct_wtcent  + rr_ct_wtcent),
    ff_ratio_parcel_mean = ff_parcel_mean / (ff_parcel_mean + rr_parcel_mean)
  ) %>%
  select(GEOID, network, drive,
         smk_ratio_ct_cent, smk_ratio_ct_wtcent, smk_ratio_parcel_mean,
         ff_ratio_ct_cent,  ff_ratio_ct_wtcent,  ff_ratio_parcel_mean)

write_csv(ct_driving_ratio, paste0(processed_path, "LAC_cleaned/ct_driving_ratios.csv"))

rm(ct_driving, ct_driving_ratio, usdafa, usdafa_la)

#'* Process household/parcel-level data (non-aggregate) * -------------------------------
parcel_driving1 <- dt_household |>
  process_times(la_city_hh, GEOID="GEOID_20",
                agg=FALSE, scale="parcel", type="driving") |> 
  mutate(GEOID=ifelse(GEOID==6037980022,6037106645,GEOID))

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


#
# NOTES/OLD CODE -----------------------------------------

# write aggregated parcel data 
data.table::fwrite(dt_household_ct, paste0(processed_path, "LAC_cleaned/dt_household_ct.csv"))
 

# # ----------- PROCESS AND WRITE WALK TIMES --------------- #
# # get walking times
# walking_times <- list()
# walking_times$ct_cent <- get_and_merge_files(density_path, "ct_cent_WALK")
# walking_times$ct_wtcent <- get_and_merge_files(density_path, "ct_wtcent_WALK")
# walking_times$household <- get_and_merge_files(density_path, "parcel_WALK")
# 
# # use la_city_hh
# # convert to wide with opportunity and cutoff merged as column name and accessibility as value
# walking_times$household_ct <- process_times(walking_times$household %>% select(-...1), 
#                                             la_city_hh %>% st_drop_geometry(), GEOID="GEOID_20", 
#                                             agg=T, scale="parcel", type="walking")# join ct data with walking times
# 
# walking_times$ct_cent <- process_times(walking_times$ct_cent, la_ctcent_dat, "walking", scale="ct_cent", agg=F, GEOID="GEOID") %>%
#   st_drop_geometry()
# 
# walking_times$ct_wtcent <- process_times(walking_times$ct_wtcent, la_ct_wtcent_dat, "walking", scale="ct_wtcent", agg=F, GEOID="GEOID") %>%
#   st_drop_geometry()
# 
# head(walking_times$household_ct) #inspect
# head(walking_times$ct_wtcent) #inspect
# 
# # merge all walking times (ct_cent, ct_wtcent, household) by geoid
# ct_walking <- walking_times$ct_cent %>%
#   left_join(walking_times$ct_wtcent, by = "GEOID") %>%
#   left_join(walking_times$household_ct, by = "GEOID") %>%
#   mutate(network_type = "Walking") 
# 
# write.csv(ct_walking, paste0(processed_path, "LAC_cleaned/ct_walking_times.csv"))
# 
# head(walking_times$ct_wtcent) #inspect
# head(walking_times$ct_cent) #inspect


  

