
library(CDCPLACES)

# 
get_CDCPlaces_dict <- function() get_dictionary()

get_CDCPlaces <- function(geography, state=STUDY_STATE, measure=NULL, county=NULL, release="2024", geometry=F, cat=NULL, age_adjust=NULL) { 
  
  get_places(
    geography = geography,
    state = state,
    measure = measure,
    county = county,
    release = release,
    geometry = geometry,
    cat = cat,
    age_adjust = age_adjust
  )
  
} 
