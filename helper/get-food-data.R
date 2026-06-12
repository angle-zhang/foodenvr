


## HELPER FUNCTIONS ------------------------------------

# General function to fetch data from ArcGIS REST services
# ID of feature layer
get_arcgis_data <- function(url) {
  require(arcgislayers)
  tryCatch({
    server <- arc_open(url)
    
    # Get all layers and tables
    layers_info <- get_all_layers(server)
    
    # Extract layers and tables
    layers <- layers_info$layers
    # Display information about first layer
    # TODO multiple layers
    feature_layer <- get_layer(server, id=layers[[1]]$id)
    
    arc_select(feature_layer)
    
  }, error = function(e) print(e))
}

# General function to download files
download_file <- function(url, destfile, unzip_dir = NULL) {
  destfile <- file.path(base_path, destfile)
  download.file(url, destfile, method = "libcurl", mode = "wb")
  if (!is.null(unzip_dir)) unzip(destfile, exdir = file.path(base_path, unzip_dir))
}

# General function to read CSV files
read_csv_file <- function(filename) {
  read_csv(file.path(base_path, filename), show_col_types = FALSE)
}

## SNAP DATA ----------------------------------------- 

# Get historical SNAP data (filtered by years)
get_snap_historical <- function(years = 1930:2021, proj_crs) { 
  read_csv_file("hist_snap_retailer_final2022/hist_snap_retailer_final2022.csv") %>%
    filter(auth_year %in% years) %>%
    st_as_sf(coords = c("x", "y"), crs = proj_crs)
}

# Download historical SNAP data
download_snap_historical <- function() { 
  download_file(
    url = "https://github.com/jshannon75/snap_retailers/raw/refs/heads/master/data/hist_snap_retailer_final2022_csv.zip",
    destfile = "hist_snap_retailer_final2022_csv.zip",
    unzip_dir = "hist_snap_retailer_final2022"
  )
}

# Get current SNAP data filtered by polygon
get_snap_current <- function(polygon, proj_crs) { 
  snap_url <- "https://services1.arcgis.com/RLQu0rK7h4kbsBq5/arcgis/rest/services/snap_retailer_location_data/FeatureServer/0/"
  
  get_layer_by_poly(snap_url, polygon, sp_rel = "contains") %>%
    st_transform(st_crs(proj_crs))
}


# reads raw data axle point of interest data for entire U.S. 
save_data_axle <- function(year=proj_year, state=proj_state, city=NULL) { 
  require(LaF)
  
  if (!is.null(city) & is.null(state)) { 
    stop("Please provide a state when filtering by city.")  
  }
  
  data_axle_path <- paste0(base_path, "hist_food_environment/", year, "_Business_Academic_QCQ.txt/")
  file_name <- paste0(year, "_Business_Academic_QCQ.txt")
  
  file_full_path <- paste0(data_axle_path, file_name)
  
  # Detect column types (assume first 1000 rows are representative)
  sample <- read.csv(file_full_path, nrows = 10)
  column_types <- sapply(sample, function(col) {
    if (is.numeric(col)) "double" else "string"
  })
  col_names <- names(sample)
  
  # Detect column types and names
  laf_file <- laf_open_csv(filename = file_full_path, 
                           sep = ",", 
                           column_types = column_types,  # adjust based on actual number and type of columns
                           column_names = col_names,
                           skip = 0)
  
  # Filtering by both state and city
  if (!is.null(state) & !is.null(city)) {
    output_path <- paste0(processed_path, "food_environment/", year, "_data_axle_", state, "_", city, ".csv")
    print("Filtering data...")
    
    rows_to_keep <- which(laf_file[, "STATE"] == state & laf_file[, "CITY"] == city)
    filtered_data <- laf_file[rows_to_keep, ]
    print(paste0("Writing data to output file: ", output_path))    
    write.csv(filtered_data, output_path)
  }
  
  # Filtering by state only
  if (!is.null(state) & is.null(city)) {
    output_path <- paste0(processed_path, "food_environment/", year, "_data_axle_", state, ".csv")
    print("Filtering data...")
    rows_to_keep <- which(laf_file[, "STATE"] == state)
    filtered_data <- laf_file[rows_to_keep, ]
    print(paste0("Writing data to output file: ", output_path))
    
    write.csv(filtered_data, output_path)
  }
  
}

# Function to load saved data axle data
get_data_axle <- function(year=proj_year, state=NULL) { 
  if (is.null(state)) { 
    stop("Please provide a state.")  
  }
  
  file_path <- paste0(processed_path, "food_environment/", year, "_data_axle_", state, ".csv")
  
  if (!file.exists(file_path)) {
    stop("File not found! Run save_data_axle() with year and state first.")
  }
  
  data <- read_csv(file_path)
  
  return(data)
}


## FOOD POI (DATA AXLE) CLEANING AND CATEGORIZATION -------------------------------------
# TODO clip to boundary 
# Cleans raw Data Axle POIs, assigns food categories via NAICS codes from a Google Sheet,
# removes geo-duplicates, and writes the result to processed_path/foodpoi_{year}.csv.
# naics_url: Google Sheet with columns 'code' and 'zhang-2025' (food category label)
save_and_clean_foodpoi <- function(year=proj_year, state=proj_state, processed_path=processed_path,
                                   boundary) {
  require(googlesheets4)
  require(data.table)
  
  poi_da <- get_data_axle(year=year, state=state) %>%
    filter(!is.na(COMPANY) & !is.na(PRIMARY.SIC.CODE))
  
  naics <- get_naics(processed_path)
  
  poida_cleaned <- poi_da %>%
    mutate(NAICS.CODE.trunc = as.numeric(str_extract(PRIMARY.NAICS.CODE, "^\\d{1,6}"))) %>%
    as.data.table()
  
  naics_dt <- as.data.table(naics) %>%
    rename("category" = "zhang-2025")
  
  temp <- naics_dt[poida_cleaned, on = .(code == NAICS.CODE.trunc), nomatch = 0]
  temp[, dummy := 1]
  temp2 <- dcast(temp, ...1 + COMPANY + ADDRESS.LINE.1 + CITY + ZIPCODE + ZIP4 + LATITUDE + LONGITUDE ~ `category`, value.var="dummy", fill=0)
  
  foodpoi <- temp2 %>%
    as.data.frame() %>%
    filter(!is.na(LONGITUDE)) %>%
    rename(id = ...1)
  
  foodpoic <- find_geo_duplicates(foodpoi, name_col="COMPANY", max_dist_m=80, jw_threshold=.9)[[1]]
  
  write_csv(foodpoic, paste0(processed_path, "foodpoi_", year, ".csv"))
}

save_naics <- function(processed_path) { 
  naics_url<-'https://docs.google.com/spreadsheets/d/1y7TxLRUXCcgd-T4_mGAXaAwAR7R00JxJDjJ9IhAucAA/edit?gid=0#gid=0'
  naics <- read_sheet(naics_url)
  write_csv(naics, paste0(processed_path, "naics", ".csv"))  
}

get_naics <- function(processed_path) { 
  read_csv(paste0(processed_path, "naics", ".csv"))  
}

# Load saved foodpoi data for a given year
get_foodpoi <- function(year=proj_year, path=processed_path) {
  file_path <- paste0(path, "foodpoi_", year, ".csv")
  if (!file.exists(file_path)) {
    stop("File not found! Run save_and_clean_foodpoi() with year and state first.")
  }
  read_csv(file_path, show_col_types=FALSE)
}

## FOOD INSPECTION DATA -------------------------------------

# Download food inspection data for LA County
download_foodinsp_lacounty <- function() { 
  download_file(
    url = "https://www.arcgis.com/sharing/rest/content/items/19b6607ac82c4512b10811870975dbdc/data",
    destfile = "foodinsp_lacounty21_24.csv"
  )
}

# Load food inspection data
get_foodinspection_lacounty <- function() { 
  read_csv_file("foodinsp_lacounty21_24.csv") 
}


## RETAIL FOOD MARKETS --------------------------------------
# Function to download retail food market data
download_retail_food_LB_PAS <- function() {
  urls <- c("markets" = "https://services1.arcgis.com/ZIL9uO234SBBPGL7/arcgis/rest/services/Retail_Food_Markets_LB_PAS_V_2023/FeatureServer", 
            "res" = "https://services1.arcgis.com/ZIL9uO234SBBPGL7/arcgis/rest/services/Restaurants_LB_PAS_V_2023/FeatureServer")  
  
  # get data and append to it using arcgis 
  data <- data.frame()
  
  for (type in names(urls)) { 
    data <- rbind(data, get_arcgis_data(urls[[type]]) %>% mutate(type=type))  
  }
  
  # check if data was retrieved
  if (is.null(data)) {
    message("Error: No data retrieved from ArcGIS service.")
    return(NULL)
  }
  
  # Standardize column names
  colnames(data) <- gsub("USER_", "", colnames(data))
  colnames(data) <- gsub("__", "_", colnames(data))
  # change everything except last column to uppercase
  last_col <- ncol(data)
  colnames(data)[1:(last_col-1)] <- toupper(colnames(data)[1:(last_col-1)]) 
  
  # Save as GeoPackage
  output_path <- file.path(base_path, "retail_food_LB_PAS_V_2023.gpkg")
  
  st_write(data, output_path, driver = "GPKG", append = FALSE)
  
  message("Retail food data saved to: ", output_path)
}


# Function to load saved retail food market data
get_retail_food_LB_PAS <- function(proj_crs) {
  file_name <- "retail_food_LB_PAS_V_2023.gpkg"
  file_path <- file.path(base_path, file_name)
  
  if (!file.exists(file_path)) {
    stop("File not found! Run download_retail_food_LB_PAS() first.")
  }
  
  st_read(file_path) %>%
    st_transform(proj_crs)  # Transform to desired CRS
}


