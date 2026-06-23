library(tidyverse)
library(CDCPLACES)
library(tmap)
library(crsuggest)
library(sf)
library(tigris)
library(tidycensus)
library(osmextract)
library(data.table)
library(broom)
library(centr)

source('./config.R')

source('./helper/data_functions.R')
source('./helper/get-food-data.R')
source('./helper/get-admin-data.R')
source('./helper/universal_variables.R')

# access_path is derived after universal_variables.R sets STUDY_COUNTY / STUDY_STATE
access_path  <- paste0(processed_path, STUDY_STATE, "_", gsub(" ", "_", STUDY_COUNTY), "_accessibility/")
origins_path <- paste0(processed_path, "origins/")
cleaned_path <- paste0(processed_path, "cleaned/")



#library(reticulate)
#py_run_file('C:/Users/angie/OneDrive/Desktop/data-analysis/0_helper-functions/get_osm_data.py')

