
# =============================================================================
# STEP D: SUMMARIZING DATA AT DIFFERENT SPATIAL SCALES
# Merges chunked accessibility output files, aggregates parcel-level measures
# to the census tract level, and merges all population representation methods
# into a single wide-format dataset for comparison.
# =============================================================================

source("0_Libraries.R")
source("./helper/gen-helper.R")

library(tidytable)

geoid_col  <- paste0("GEOID_", substr(STUDY_YEAR, 3, 4))
study_area <- if (!is.null(STUDY_CITY)) gsub(" ", "_", STUDY_CITY) else gsub(" ", "_", STUDY_COUNTY)

if (!dir.exists(cleaned_path)) dir.create(cleaned_path, recursive = TRUE)

# ------ LOAD SPATIAL CONTEXT ------
la_ct   <- get_census_tracts(crs = proj_crs, state = STUDY_STATE,
                               year = STUDY_YEAR, county = STUDY_COUNTY)
study_boundary <- get_city_boundary(proj_crs)

study_ct <- la_ct %>%
  dplyr::filter(lengths(sf::st_intersects(., study_boundary)) > 0) %>%
  sf::st_transform(proj_coord_crs)

la_ct_key <- read_csv(paste0(origins_path, "ct_key.csv"))

density_path <- file.path(access_path, "density", study_area, "CATG")

# ------ LOAD PARCEL DATA (if available) ------
has_parcels <- !is.null(HOUSEHOLDS_PATH)

if (has_parcels) {
  la_hh <- load_address_points(HOUSEHOLDS_PATH, la_ct, proj_crs)
  study_hh <- la_hh %>%
    dplyr::filter(.data[[geoid_col]] %in% study_ct$GEOID)
}

# ------ MERGE CHUNKED OUTPUT FILES ------
dt_ct_cent   <- get_and_merge_files(density_path, "ct_cent_CAR")
dt_ct_wtcent <- get_and_merge_files(density_path, "ct_wtcent_CAR")

dt_ct_cent1   <- dt_ct_cent   %>% calc_relative_measures()
dt_ct_wtcent1 <- dt_ct_wtcent %>% calc_relative_measures()

# ------ PROCESS CT CENTROID METHODS ------
dt_ct_centm   <- process_times(dt_ct_cent1   %>% dplyr::select(-row.names), la_ct_key,
                               type = "driving", scale = "ct_cent",   agg = FALSE)
dt_ct_wtcentm <- process_times(dt_ct_wtcent1 %>% dplyr::select(-row.names), la_ct_key,
                               type = "driving", scale = "ct_wtcent", agg = FALSE)

# ------ PROCESS PARCEL METHOD (if available) ------
if (has_parcels) {
  dt_household  <- get_and_merge_files(density_path, "parcel_CAR")
  dt_household1 <- dt_household %>% calc_relative_measures()
  
  dt_household_ct <- process_times(
    dt_household1 %>% dplyr::select(-row.names),
    study_hh %>% sf::st_drop_geometry(),
    GEOID = geoid_col, agg = TRUE, scale = "parcel", type = "driving"
  )
  
  data.table::fwrite(dt_household_ct, paste0(cleaned_path, "dt_household_ct.csv"))
  
  # parcel-level wide format (non-aggregated)
  parcel_driving1 <- dt_household1 %>%
    process_times(study_hh, GEOID = geoid_col,
                  agg = FALSE, scale = "parcel", type = "driving")
  # NOTE: any study-area-specific GEOID corrections go here, e.g.:
  # parcel_driving1 <- parcel_driving1 %>% dplyr::mutate(GEOID = dplyr::recode(GEOID, "06037980022" = "06037106645"))
  
  parcel_drivingdt <- as.data.table(parcel_driving1) %>%
    melt(id.vars       = c("GEOID", "id"),
         variable.name = "features",
         value.name    = "count") %>%
    tidytable::separate_wider_delim(features, delim = "_",
                                    names = c("network", "type", "drive", "pop_rep"),
                                    too_many = "merge", too_few = "align_start") %>%
    drop_na(count)
  
  data.table::fwrite(parcel_drivingdt, paste0(cleaned_path, "parcel_drivingdt.csv"))
}

# ------ LOAD USDA FOOD ATLAS FOR COMPARISON ------
usda_path <- paste0(base_path, "USDA_foodatlas/FoodAccessResearchAtlasData2019.xlsx")
if (file.exists(usda_path)) {
  usdafa    <- openxlsx::read.xlsx(usda_path, sheet = 3)
  study_boundary_geoids <- study_ct %>% sf::st_drop_geometry() %>% dplyr::select(GEOID) %>% dplyr::pull()
  usdafa_la <- usdafa %>%
    dplyr::mutate(GEOID = as.character(CensusTract)) %>%
    dplyr::filter(GEOID %in% study_boundary_geoids) %>%
    dplyr::select(GEOID, dplyr::starts_with("LA1"), LAhalfand10, dplyr::starts_with("LAT"))
} else {
  usdafa_la <- NULL
  message("USDA Food Atlas file not found at ", usda_path, " — skipping USDA join.")
}

# ------ MERGE ALL CT-LEVEL DATA ------
ct_driving <- dt_ct_centm %>%
  dplyr::select(-id) %>%
  dplyr::left_join(dt_ct_wtcentm, by = "GEOID") %>%
  {if (has_parcels) dplyr::left_join(., dt_household_ct, by = "GEOID") else .} %>%
  dplyr::select(-dplyr::any_of("id")) %>%
  tidyr::pivot_longer(!GEOID, names_to = "features", values_to = "count") %>%
  tidyr::separate_wider_delim(features, delim = "_",
                               names = c("network", "type", "drive", "pop_rep"),
                               too_many = "merge", too_few = "align_start") %>%
  tidyr::pivot_wider(names_from = pop_rep, values_from = count) %>%
  {if (!is.null(usdafa_la)) dplyr::left_join(., usdafa_la, by = "GEOID") else .}

write_csv(ct_driving, paste0(cleaned_path, "ct_driving_times.csv"))
rm(ct_driving, usdafa, usdafa_la)

# ------ MERGE PARCEL DATA WITH CT CONTEXT (if available) ------
if (has_parcels) {
  parcel_driving_all <- parcel_drivingdt %>%
    tidytable::left_join(ct_driving, by = c("GEOID", "type", "drive", "network"))
  data.table::fwrite(parcel_driving_all, paste0(cleaned_path, "parcel_driving_all.csv"))
}

rm(dt_ct_cent, dt_ct_wtcent, dt_ct_cent1, dt_ct_wtcent1)
gc()
