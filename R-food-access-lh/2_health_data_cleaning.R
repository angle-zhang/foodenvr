source("./0_Libraries.R")
library(openxlsx)



# ------------------ pulling geocoded data ------------------
# TODO 
# - Verify these files are correct ones payal was referring to
# - Test association between household-level measures, census tract level, and zip-code measures (DO LATER) in participant population; 
  # merge geocodes and participant BMI/CDE data 
  # merge all participant data (p1...p4)

geocoding_path <- "../../0_shared-data/latino-health-elsendero/raw/Geocoding/Complete/"
p1mm_geodata <- read.xlsx(paste0(geocoding_path, "MothersMilk (Batch 3 Final Geocoding with All Edits 25NOV_HL.xlsx).xlsx")) %>%
  filter(!is.na(NewLatitude)) |>
  st_as_sf(coords=c("NewLatitude", "NewLongitude"), crs=proj_crs) |>
  mutate(mergeID = row_number())
# TODO ask payal why P1 and P2 organized differently? oes P1 and P2 have DOV and DOB data? 

#'* DOB enrichment and DOV enrichment sheets *
# TODO decide if using DOB or DOV
# TODO decide if using child observation (if so we want to use DOB as well as DOV)
p2_geodataDOB <- read.xlsx(paste0(geocoding_path, "NIMHDP50MasterProjec-Project2ResidentialH_DATA_2025-06-06_Enriched_0925_SSI.xlsx"), sheet="DOB_Enrichment_SSI_P2") %>%
  filter(!is.na(X)) |>
  st_as_sf(coords=c("X", "Y"), crs=proj_crs)|>
  mutate(mergeID = nrow(p1mm_geodata) + row_number())

p2_geodataDOV <- read.xlsx(paste0(geocoding_path, "NIMHDP50MasterProjec-Project2ResidentialH_DATA_2025-06-06_Enriched_0925_SSI.xlsx"), sheet="DOV_Enrichment_SSI_P2") %>%
  filter(!is.na(X)) |>
  st_as_sf(coords=c("X", "Y"), crs=proj_crs) |>
  mutate(mergeID = nrow(p1mm_geodata) + nrow(p2_geodataDOB) + row_number())

# TODO get list of all (coord) geometries to run gen_measures code on
# TODO need to do same with GEOIDs
combined_geo <- p1mm_geodata |> select(mergeID, geometry) |>
  rbind(p2_geodataDOB |> select(mergeID, geometry)) |>
  rbind(p2_geodataDOV |> select(mergeID, geometry))

# ------------------ Calculating FE measures for geocoded data ------------------
# TODO calculate food environment measures using gen_measures
# TODO 


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