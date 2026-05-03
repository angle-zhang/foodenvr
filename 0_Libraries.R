
          
library(tidyverse)
library(CDCPLACES)
library(tmap)
library(crsuggest)
library(sf)
library(tigris)
library(dplyr)
library(osmextract)
library(data.table)
library(broom)
#library(osmdata)



# 1
library(centr)

# run once - only for SSI computers
# library(rJavaEnv)
# java_quick_install(version = 21)
# Sys.setenv(JAVA_HOME="C:\\Users\\lab.DTS-MJ0LQJJJ\\AppData\\Local//R//cache//R//rJavaEnv//installed//windows//x64//21")

# for other computers
# Sys.setenv(JAVA_HOME="C:\\Program Files\\Java\\jdk-21")

rJavaEnv::java_check_version_rjava()
options(java.parameters = "-Xmx12G")
library(r5r)

base_path <- "../0_shared-data/food-environment-measures/raw/"
processed_path <- "../0_shared-data/food-environment-measures/processed/"
access_path <- paste0(processed_path, "LAC_accessibility")

source('./helper/data_functions.R')
source('./helper/get-food-data.R')
source('./helper/get-la-county-admin-data.R')
source('./helper/universal_variables.R')

#source('../../0_helper-functions/get-health-data.R')

library(googlesheets4)
#library(reticulate)
#py_run_file('C:/Users/angie/OneDrive/Desktop/data-analysis/0_helper-functions/get_osm_data.py')

