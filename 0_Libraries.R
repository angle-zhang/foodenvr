
          
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
#library(osmdata)

library(centr)

base_path <- "../0_shared-data/food-environment-measures/raw/"
processed_path <- "../0_shared-data/food-environment-measures/processed/"
access_path <- paste0(processed_path, "LAC_accessibility")

# TODO only include these when necessary
source('./helper/data_functions.R')
source('./helper/get-food-data.R')
source('./helper/get-la-county-admin-data.R')
source('./helper/universal_variables.R')

#source('../../0_helper-functions/get-health-data.R')

#library(reticulate)
#py_run_file('C:/Users/angie/OneDrive/Desktop/data-analysis/0_helper-functions/get_osm_data.py')

