source("0_Libraries.R")
source('helper/geo-duplicate-finder.R')
source('helper/geocoder.R')

# TODO combine this file with data collection
# ------ GET BUFFER -------- #
lac_boundary <- get_county_boundary(proj_crs)
lac_buffer <- st_buffer(lac_boundary, proj_buffer_size) # get buffer in proj_buffer_size mile 

# ------ GET CENSUS TRACT DATA FOR PROJECT ------ #

## clip to boundary
# This currently doesnt clip to any boundary
la_ct <- get_census_tracts(path=base_path, proj_crs, state=proj_state, year=proj_year, county=proj_county)
la_cb <- get_census_blocks(path=base_path, proj_crs, state=proj_state, year=proj_year, county=proj_county)

# inspect
tm_shape(la_ct)  +
  tm_polygons(col="blue") 

# ------ CALCULATE AND SAVE CENTROIDS OF CTs FOR COUNTY ------ #
# ONLY RUN ONCE
# calc_and_save_lac_centroids(la_ct, la_cb, proj_crs, processed_path)

la_ct_wtcent_dat <- get_lac_weight_centroids(processed_path, county=proj_county)
la_ctcent_dat <- get_lac_centroids(processed_path, county=proj_county)

# TODO re-geocode data

# ------ CLEAN AND SAVE FOOD POI CATEGORIES USING METHOD FROM HIRSCH ET AL., 2021 ------ #
# TODO clip to a boundary
save_and_clean_foodpoi(year=proj_year, state=proj_state, processed_path=processed_path, boundary=lac_buffer)
foodpoi <- get_foodpoi() |> 
  st_as_sf(coords=c("LONGITUDE", "LATITUDE"), crs=proj_crs)

v <- foodpoi[foodpoi$CITY=="LOS ANGELES",]

# TODO FIGURE OUT WHY THIS ISN'T MAPPING ONTO THE MAP
tm_shape(v) + 
  tm_dots(col="green", size=2) + 
  tm_shape(lac_boundary |> st_transform(proj_crs)) + 
  tm_polygons(col="grey")
 
# PLOT FOOD POI to make sure it worked
# ------ LOAD AND CLEAN FOOD MARKET POI DATA ------ #
# TODO  cleaning names 
# find all names with # followed by number #9357

length(unique(foodmarket_merged$FACILITY_NAME)) # get all unique names with # followed by number
# TODO Move to Rmd file
#'*sensitivity analysis: inspect to see if chains are consistently coded *
# We find that the chains are consistently coded 
# 697 rows for NAICS and name pairs that had a count >5
# only 1 inconsistency was found "albertson's delicatssen" was coded as restaurant and supermarket
#' # kept as is since there may be reason for coding this way
#' chains <- temp[, .(count = .N), by = .(`zhang-2025`, code, COMPANY)][count>5]
#' 
#' 
#' 
#' # TODO clip to a buffer
#' 
#' 
#' foodmarket_names <- foodmarket %>%
#'   mutate(FACILITY_NAME = str_replace_all(FACILITY_NAME, "#\\d+", "")) 
#' 
#' unique(foodmarket_names$FACILITY_NAME) 
#' # repalce @ with AT
#' foodmarket_cleaned <- foodmarket_merged %>%
#'   mutate(FACILITY_NAME = trimws(FACILITY_NAME)) %>%
#'   mutate(FACILITY_NAME = str_replace_all(FACILITY_NAME, "#\\d+", "")) %>%
#'   mutate(FACILITY_NAME = str_replace_all(FACILITY_NAME, "# \\d+", "")) %>%
#'   mutate(FACILITY_NAME = gsub("@", "AT", FACILITY_NAME)) %>%
#'   mutate(FACILITY_NAME = trimws(FACILITY_NAME)) 
#' # remove trailing spaces
#' 
#' # merge with chain names
#' foodmarket_cleaned1 <- foodmarket_cleaned %>%
#'   fuzzyjoin::stringdist_left_join(chains2, by=c("FACILITY_NAME"="COMPANY"), max_dist=1) %>%
#'   mutate(chain = ifelse(sic_codes!="NULL", TRUE, FALSE)) 
#' 
#' # TODO remove duplicates?
#' 
#' length(unique(chains2$COMPANY))
#' nrow(foodmarket_cleaned1 %>% filter(chain))
#' 
#' temp <- chains1 %>%
#'   count(COMPANY)
#' 
#' print(paste("Unique names found after removing numbers with # sign before them:",  
#'             length(unique(foodmarket_merged$FACILITY_NAME))- length(unique(foodmarket_cleaned$FACILITY_NAME)))) # get all unique names with # followed by number
#' 
#' #'* DON'T DELETE METHOD FOR OBTAINING CHAINS AND ASSOCIATED SIC CODES *---------------------------------------------------
#' chains <- poi_da %>%
#'   group_by(COMPANY) %>%
#'   summarise(count = n()) %>%
#'   arrange(desc(count)) %>%
#'   filter(count>=5)
#' 
#' ## for each name, get the most common primary sic code
#' chains_sic <- poi_da %>%
#'   filter(COMPANY %in% chains$COMPANY) %>%
#'   group_by(COMPANY, PRIMARY.SIC.CODE) %>%
#'   summarize(count=n()) %>%
#'   slice_max(count)
#' 
#' chains1 <- chains %>% merge(chains_sic, by="COMPANY") %>%
#'   select(COMPANY, PRIMARY.SIC.CODE, count.x) %>%
#'   mutate(sic4 = substr(PRIMARY.SIC.CODE, 1, 4)) %>%
#'   filter(sic4 %in% sic_list4$.) %>% # filter for the ones we are interested in
#'   group_by(COMPANY) %>%
#'   summarize(sic_codes=list(PRIMARY.SIC.CODE)) 
#' 
#' # put word market after SIC codes starting with 5411 unless they already have "market" in the
#' chains2 <- chains1 %>%
#'   mutate(COMPANY=ifelse(grepl("MARKETPLACE", COMPANY), gsub(" MARKETPLACE", "", COMPANY), COMPANY)) %>%
#'   # TODO do something about costco
#'   rowwise() %>%
#'   mutate(
#'     COMPANY = if (any(str_starts(as.character(sic_codes), "5411")) && !str_detect(str_to_lower(COMPANY), "market")) 
#'       paste0(COMPANY, " MARKET") 
#'     else COMPANY
#'   ) %>%
#'   ungroup() %>%
#'   rbind(chains1) %>%
#'   unique()
#' 
#' 
#' # TODO complex strat: 


