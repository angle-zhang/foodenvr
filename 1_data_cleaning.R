source("0_Libraries.R")
source('helper/geo-duplicate-finder.R')
source('helper/geocoder.R')

# ------ LOAD AND CLEAN FOOD MARKET POI DATA ------ #
# TODO  cleaning names 
# find all names with # followed by number #9357

length(unique(foodmarket_merged$FACILITY_NAME)) # get all unique names with # followed by number

# ------ CLEAN AND GET CATEGORIES NAMES FROM HIRSCH ET AL., 2021 ------ #
# TODO put this in a function
require(googlesheets4)

# Get poi data 
poi_da <- get_data_axle(year=2022, state="CA") %>%
  filter(!is.na(COMPANY) & !is.na(PRIMARY.SIC.CODE))

# TODO wrap this in a function
# TODO make this a file not a link
naics <- read_sheet('https://docs.google.com/spreadsheets/d/1y7TxLRUXCcgd-T4_mGAXaAwAR7R00JxJDjJ9IhAucAA/edit?gid=0#gid=0') 

# TODO make key to reassign chains to the same NAICS code
code_cols <- names(poi_da)[grepl("NAICS\\.CODE", names(poi_da))] # get all column names with SIC)

poida_cleaned <- poi_da %>% # create one row per sic code in poi data
  mutate(NAICS.CODE.trunc = as.numeric(str_extract(PRIMARY.NAICS.CODE, "^\\d{1,6}"))) %>%
  as.data.table()

naics_dt <- as.data.table(naics) %>%
  rename("category"="zhang-2025")

temp <- naics_dt[poida_cleaned, on = .(code == NAICS.CODE.trunc), nomatch = 0] # select variables in poida_cleaned between sic code
temp[, dummy:=1]
temp2 <- dcast(temp, ...1 + COMPANY + ADDRESS.LINE.1 + CITY + ZIPCODE + ZIP4 + LATITUDE + LONGITUDE ~ `category`, value.var="dummy", fill=0) # summarize to wide format with new columns representing food POI categories

# TODO print number of missing observations
foodpoi <- temp2 %>%
  as.data.frame() %>%
  filter(!is.na(LONGITUDE)) %>%
  rename(id=...1)

# remove duplicates
# TODO find_geo_duplicates is removing latitude and longitudde
foodpoi_dup <- find_geo_duplicates(foodpoi, name_col="COMPANY", max_dist_m = 80, jw_threshold = .9)

foodpoic <- foodpoi_dup[[1]]

# TODO PLOT FOOD POI

# TODO re-geocode data

# write foodpoi to file
write_csv(foodpoic, paste0(processed_path, "foodpoi_2022.csv")) # NEED TO CHANGE TO 2024 data

#'*sensitivity analysis: inspect to see if chains are consistently coded *
# find that the chains are consistently coded 
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


