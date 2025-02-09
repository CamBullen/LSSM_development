#----------------------------------------------------------------------------
# Script:  LSSM_configuration.R
# Created: September 2024
#
# Purpose: Create and load initial data structures for the LSSM. 
#
# Notes:
#  - 
#================================== Load require packages =================================
# check for any required packages that aren't installed and install them
required.packages <- c( "ggplot2", "reshape2", "lubridate", "dplyr", "stringr",
                        "rmarkdown","knitr", "tinytex", # "kableExtra", currently causing trouble.
                        "seacarb", "gsw", "truncnorm")

# Other packages that might be useful. 
# "tidyr", "raster", "stringr", "rasterVis",
# "RColorBrewer", "factoextra", "ggpubr", "cluster", 
# "diffeR", "vegan", "ranger", "e1071", "forcats", "measures", "caret", "PresenceAbsence"
# "randomForest", "spatialEco", "xlsx", "robustbase", "biomod2", "sp", "magrittr", "binr", 'gwxtab'

uninstalled.packages <- required.packages[!(required.packages %in% installed.packages()[, "Package"])]

# install any packages that are required and not currently installed
if(length(uninstalled.packages)) install.packages(uninstalled.packages)

# require all necessary packages
lapply(required.packages, require, character.only = TRUE)
#lapply(required.packages, library, character.only = TRUE)
version$version.string

#==== Configuration ====
latitude  <- 49.2827   # Vancouver's latitude
longitude <- -123.1207 # Vancouver's longitude

B_init      <- 0.025  # Initial mass of sporophyte (est. at 25 mg based on ChatGPT)
B_max       <- 9.23   # Max biomass for an adult Nereo. Calculated from field results (Weigel and Pfister 2021)
r_max       <- 0.065  # Maximum daily growth rate, assuming 6 month growth and mature plant is 9.23 kg 

data_dir <- "C:/Data/Git/LSSM_development/Data"
DEB_dir  <- "C:/Data/Git/LSSM_development/DEB"

# Growth period
# Dates set to match 2023 BATI mooring data
start_date <- as.POSIXct("2023-05-03 16:00:00", format = "%Y-%m-%d %H:%M:%S", tz = "America/Los_Angeles")
end_date   <- as.POSIXct("2023-09-29 23:00:00", format = "%Y-%m-%d %H:%M:%S", tz = "America/Los_Angeles")
hour_stamps <- seq(from = start_date, to = end_date, by = "hour")

# Create compatible x-axis labels
day_stamps <- hour_stamps %>%
  as.Date() %>%                                          # Convert timestamps to Date
  unique() %>%                                           # Get unique dates
  .[. >= as.Date(start_date) &  . <= as.Date(end_date)]  # Filter dates within the range
day_stamps <- as.Date( day_stamps )
day_stamps <- day_stamps[-length(day_stamps)] # KLUDGE!!

#difftime(end_date, start_date, units = "days")

# Growth parameters
B_init      <- 0.025  # Initial mass of sporophyte (est. at 25 mg based on ChatGPT)
B_max       <- 9.23   # Max biomass for an adult Nereo. Calculated from field results (Weigel and Pfister 2021)
r_max       <- 0.065  # Maximum daily growth rate, assuming 6 month growth and mature plant is 9.23 kg 
sp_start    <- 0.005  # Established sporophyte mass (5 g)
wet_to_dry  <- 0.13   # Water content of Nereo (Bullen et al. 2024)
dry_to_C    <- 0.25   # Carbon content of Nereo (dry) (Bullen et al. 2024)

#---- Environmental influence on growth rate ----
T_opt     <- 10        # Optimal temperature (°C)
T_max     <- 14        # Temperature range for growth (°C)
DLI_opt   <- 30        # mol/m2/day
DLI_range <- 20        # mol/m2/day (+/-)

#---- Anticipated parameters  ----
moText <- c( "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
# Elemental stuff in moles, complex/diverse molecules in g. 
ounits <- list( sizeu = 'ha',
                tempu = 'C',
                saltu = 'ppt',
                DO2u  = 'mol/m3',
                DICu  = 'mol/m3',
                DOCu  = 'g/m3',
                POCu  = 'g/m3',
                NOXu  = 'g/m3',
                ph    = 'pH')



#==== Functions ====

#---- Utility growth functions ----
# Logistic growth, with option for temperature and light factors.
logistic_growth <- function(B0, K, r, step, temp=1, lite=1) {
  B_predicted <- K / (1 + ((K - B0) / B0) * exp(-r * step * temp * lite))
  return(B_predicted)
}

# Calculate temperature effect on growth rate
# Pontier shows growth rate relatively stable below 10C, declines to about 1/2 by 14C
t_scale <- function(T) {
  scaled <- ifelse(T <= 10, 1, 0.5 / (T / T_max * 0.7))
  return( scaled )
}

# Light-dependent growth rate function
# Pontier shows growth rate peaks ~30 DLI. Simplify their decline to be 1/2 on both sides  
DLI_scale <- function(lite) {
  #(0.75*((lite - DLI_opt)^.5) / (DLI_range^2))
  1 - (((lite - DLI_opt) / DLI_range)^2) * 0.5
}


#==== Load and prep data ====

# Uses hard-coded name for source text file. 
# Assumes seawater CO2 measurements are what we want. 
# sw CO2 measured in ppm which is euqivalent to uatm requred by carb().
# Summarizes several years of data into a 'climatology', and interpolates missing days.
LoadAkFerryCO2Data <- function(){
  x<- read.csv(paste(data_dir, "HakaiColumbiaFerryResearch.txt", sep="/"))
  
  # Muck about with the date to 1) standardize on 6 digits, 2) replace year.
  a  <- ifelse(nchar(x$s.PC_Date) < 6, paste0("0", x$s.PC_Date), x$s.PC_Date)
  aa <- as.Date( a, format = "%d%m%y" )
  
  # Pull the data we want: this is in ppm units. 
  b <- x$s.calibrated_SW_xCO2_dry
  
  # Build a dataframe
  #foo       <- data.frame( "date" = aa, "SW_CO2" = b)
  #CO2_daily <- data.frame( "month"=month(foo$date), "day"=day(foo$date), "CO2"=foo$SW_CO2  )
  CO2_daily <- data.frame("month"=month(aa), "day"=day(aa), "CO2"=b )
  
  # Get the daily mean for available dates from Oct 2017 to Oct 2019
  CO2_daily <- CO2_daily %>%
    group_by(month, day) %>%
    summarise(
      CO2mn = mean(CO2, na.rm = TRUE),   # Mean of SW CO2
    )
  
  aa <- as.Date(paste("2023", CO2_daily$month, CO2_daily$day, sep='-'), format = "%Y-%m-%d")
  CO2_daily$date <- aa
  
  return(CO2_daily)
}

# Take the daily AK data make it match the BATI mooring days (i.e., extrapolate)
PrepAKFerryCO2Data <- function(dCO2, all_days){
  
  # Start with some dates on the CO2 data. Needs a faux year
  # full_dates <- as.Date(paste("2023", dCO2$month, dCO2$day, sep='-'), format = "%Y-%m-%d")
  # Expand the frame to include all the days in all_days
  expanded_data <- data.frame(
    Date = all_days,
    #    dCO2 = ifelse(all_days %in% full_dates, dCO2$CO2mn[match(all_days, full_dates)], NA)
    dCO2 = ifelse(all_days %in% dCO2$date, dCO2$CO2mn[match(all_days, dCO2$date)], NA)
  )
  
  # Interpolate the NAs created above
  expanded_data$dCO2 <- interpolateC02NAs(expanded_data$dCO2)
  return(expanded_data)
}

# Interpolate missing daily values for ambient seawater pCO2 values
#   Interpolated values are the mean of the last 3, next valid values. 
interpolateC02NAs <- function(series) {
  for (i in seq_along(series)) {
    if (is.na(series[i])) {
      # Get the three previous valid values
      prev_values <- tail(series[1:(i-1)][!is.na(series[1:(i-1)])], 3)
      
      # Get the next valid value
      next_value <- head(series[(i+1):length(series)][!is.na(series[(i+1):length(series)])], 1)
      
      # Compute the average if we have enough valid values
      if (length(prev_values) == 3 && length(next_value) == 1) {
        series[i] <- mean(c(prev_values, next_value), na.rm = TRUE)
      } else {
        series[i] <- mean(c(prev_values), na.rm = TRUE)
      }
    }
  }
  return(series)
}

Load2023MooringData <- function(){
  ctd<- read.csv(paste(data_dir, "ctd_surface_cond_moorings2023.csv", sep="/"))
  
  # set data types
  ctd$date_time<- ymd_hms(ctd$date_time,  tz = "America/Vancouver")
  ctd$temperature_C<- as.numeric(ctd$temperature_C)
  ctd$salinity_psu<- as.numeric(ctd$salinity_psu)
  ctd$depth_m<- as.numeric(ctd$depth_m)
  
  # Add year month and day in separated columns
  ctd$year<- year(ctd$date_time)
  ctd$month<- month(ctd$date_time)
  ctd$day<- day(ctd$date_time)
  ctd$dmy = dmy(paste(ctd$day, ctd$month, ctd$year, sep="-"))
  colnames(ctd)[13]<- "ymd"
  
  # classify moorings based on environmental clusters to merge and plot 
  # ctd$cluster<- NA
  # 
  # ctd[ctd$site == "mooring1", "cluster"]<- "5"
  # ctd[ctd$site == "mooring2", "cluster"]<- "5"
  # ctd[ctd$site == "mooring3", "cluster"]<- "5"
  # ctd[ctd$site == "mooring4", "cluster"]<- "2"
  # ctd[ctd$site == "mooring5", "cluster"]<- "2"
  # ctd[ctd$site == "mooring6", "cluster"]<- "4"
  # ctd[ctd$site == "mooring7", "cluster"]<- "4"
  # ctd[ctd$site == "mooring8", "cluster"]<- "5"
  
  return(ctd)
}

# Extract Temp and Salinty from specified BATI mooring. 
PrepBATIMooringData <- function( moor_dat, sdate, edate){
  
  # Create index for all hourly data between specified start/end months
  m_idx <- moor_dat$date_time > sdate & moor_dat$date_time < edate
  ts_out <- data.frame( 
    cbind( "month" = month( moor_dat[ m_idx, "date_time" ]),
           "day"   = day( moor_dat[ m_idx, "date_time" ]),
           "hour"  = hour( moor_dat[ m_idx, "date_time" ]),
           "temp"  = moor_dat[ m_idx, "temperature_C" ],
           "salt"  = moor_dat[ m_idx, "salinity_psu" ])
  )
  
  # Now ensure unique tuples of month, day, hour, average if necessary. 
  ts_out <- ts_out %>%
    group_by(month, day, hour) %>%
    summarise(
      temp = mean(temp, na.rm = TRUE),   # Mean of temp
      salt = mean(salt, na.rm = TRUE)    # Mean of salt
    )
  
  return(ts_out)
}  

# Summarise mooring data to daily for parameter-based model
MooringtoDays <- function( hrly_moor ){
  day_dat <- hrly_moor %>%
    group_by(month, day) %>%
    summarise(
      temp = mean(temp, na.rm = TRUE),   # Mean of temp
      salt = mean(salt, na.rm = TRUE)    # Mean of salt
    )
  day_dat$date <-as.Date(paste("2023", day_dat$month, day_dat$day, sep='-'), format = "%Y-%m-%d")
  return(day_dat)
}

# Calculate total alkalinity from salinity
CalcAlk <- function( salt ) {
  TA <- (48.7709 * salt + 606.23) # μmol kg-1 
  TA <- TA / 1000 # mol kg-1
  return( TA )  
}

#==== Simulating insolation ====

# Simulate hourly light levels for timestamps (analytic period)
# NOTE q_mult fudge factor
HourlyLightSim <- function( ts, lat, lon ){
  
  light_PAR <- CalculatePhotons( 
    solar_elevation_angle( ts, lat, lon )
  )
  return(light_PAR)
}
  
# Aggregate hours to days. 
# NOT ideal as this does not use actual DATE/time so a bit offset.
DailyLight <- function( days, hr_PAR ){
  # Currently not using days, but should. :\
  paste( "Working with", length( hr_PAR) /24, "days of light data ...")
  par_daily <- split(hr_PAR, ceiling(seq_along(hr_PAR) / 24))
  
  # initialize target ... 
  DLI <- numeric(length(par_daily))
  
  # Calculate average PAR for each day
  for (i in seq_along(par_daily)) {
    ave_par <- mean(par_daily[[i]])
    q_mult <- 1.75
    DLI[i] <- (ave_par * q_mult * 3600 *24) / 1e6
  }
  return( DLI )
}

# Function to calculate the solar declination angle (in degrees) based on the day of the year
solar_declination <- function(day_of_year) {
  23.44 * sin((360 / 365) * (day_of_year - 81) * pi / 180)
}

# Function to calculate the hour angle (in degrees) based on the local solar time
hour_angle <- function(time) {
  # Local Solar Time (LST) is approximated here as the hour in UTC + longitude / 15
  local_time <- hour(time) + (minute(time) / 60)
  LST <- local_time + longitude / 15
  15 * (LST - 12) # Convert to degrees
}

# Function to calculate the solar elevation angle (in degrees)
solar_elevation_angle <- function(time, lat, lon) {
  day_of_year <- yday(time) # Day of the year
  declination <- solar_declination(day_of_year)
  hour_ang <- hour_angle(time)
  
# Convert to radians for trigonometric calculations
  declination_rad <- declination * pi / 180
  latitude_rad <- lat * pi / 180
  hour_ang_rad <- hour_ang * pi / 180
  
# Calculate the solar elevation angle in radians
  sin_alpha <- sin(latitude_rad) * sin(declination_rad) +
    cos(latitude_rad) * cos(declination_rad) * cos(hour_ang_rad)
  
# Convert back to degrees
  solar_angle <- asin(sin_alpha) * 180 / pi
  
# And replace negative values with 0 (i.e., just dark)
  solar_angle[ solar_angle < 0] <- 0

  return( solar_angle ) # Return the angle, ensuring it's non-negative
#return(max(solar_angle, 0)) # Return the angle, ensuring it's non-negative
}

# Function to calculate PAR (Photon Flux Density in mol photons/m²/s) based on the solar elevation angle
CalculatePhotons <- function(solar_angle) {
  # Assume a clear-sky model for simplicity:
#  if (solar_angle <= 0) return(0) # No sunlight when the sun is below the horizon
  
  # Empirical estimate of solar irradiance based on solar angle (in W/m²)
  I <- 1361 * sin(solar_angle * pi / 180) # 1361 W/m² is the solar constant
  
  # Approximate PAR as 45% of total solar irradiance
  I_PAR <- 0.45 * I
  
  # Jan22: Don't think I need this conversion ... 
  # Convert to Photon Flux Density (mol photons/m²/s)
  # Using a conversion factor (4.57e-6 mol/W/s) based on average photon energy
  # photon_flux_density <- I_PAR * 4.57e-6 * 3600
  
  return( I_PAR )
}



#==== Plotting and data display ====

PlotInputs <- function( indat, ptitle ){
  colnames( indat ) <- c( "temp", "nutrients", "DIC", "light")
  see_in <- data.frame(
              cbind( "hour" = 1:dim(indat)[[1]], indat))
  
  melt_in <- melt( see_in, id.vars ="hour" )

  ggplot(melt_in) +
    geom_point( aes(x=hour, y=value), size=0.4, color="darkgreen") +
    facet_wrap(~variable, ncol = 2, scales = "free_y") +
    labs(x = "Cumulative hours", title = ptitle ) +
 #   theme_classic() +
    theme(plot.title = element_text(hjust = 0.5))
}

PlotAllDEBResults <- function( deb_out ){
  
  par(mfrow=c(3,3), mar=c(1,4,3,2))
  for (i in colnames(deb_out)[3:8] ){
    plot( deb_out[, i]~deb_out$days, type='l', xlab="", xaxt = "n", ylab=i ) }
  par(mar=c(4,4,0,2))
  for (i in colnames(deb_out)[9:11] ){
    plot( deb_out[, i]~deb_out$days, type='l', xlab="Days", ylab=i ) }
  
  par(mar=c(1,4,3,2))
  for (i in colnames(deb_out)[12:17] ){
    plot( deb_out[, i]~deb_out$days, type='l', xlab="", xaxt = "n", ylab=i ) }
  par(mar=c(4,4,0,2))
  for (i in colnames(deb_out)[18:20] ){
    plot( deb_out[, i]~deb_out$days, type='l', xlab="Days", ylab=i ) }
  
  par(mar=c(1,4,3,2))
  for (i in colnames(deb_out)[21:23] ){
    plot( deb_out[, i]~deb_out$days, type='l', xlab="", xaxt = "n", ylab=i ) }
  par(mar=c(4,4,0,2))
  for (i in colnames(deb_out)[24:26] ){
    plot( deb_out[, i]~deb_out$days, type='l', xlab="Days", ylab=i ) }
}


# A function (from 'gsw') to convert conductivity to psu, note dependence on T and P.
#   salinity = gsw.SP_from_C(conductivity, temperature, pressure)
# BUT conductivity values seem to be 2 orders of magnitude off?


#--------------  STUB FUNCTIONS ---------------

# Input either a shape file name or the shape file itself

InitializeClusters <- function( mapdat ){
  
  aCluster <- list( cname = "", 
                    size = 10.0,
                    temp = 15.0,
                    salt = 30.0,
                    NOX  = 99.0,
                    DO2  = 99.0,
                    DIC  = 99.0,
                    DOC  = 99.0,
                    POC  = 99.0,
                    DCO2 = 1.0,
                    carbA  = 1.0, 
                    carb   = 1.0,
                    bicarb = 1.0,
                    ph     = 7.0 )  
  
  z <- vector( "list", 6)
  
  for (i in 1:length(mapdat)) {
    j <- aCluster
    j$cname <- paste0( "cluster ", i )
    z[[i]] <- j
  }
  
  return(z)
}


# Create necessary GLOBAL data strUctures and populate with initial state.
# These structures will be lists (1 to n) of a list of attributes.
InitializeSimulation <- function( nMonths, firstMo, clusts ){
  
  aState <- list( month = "", 
                  clusters = clusts
  )
  
  oStates <- vector("list", nMonths)
  
  moIdx <- monthIndex( firstMo, moText )
  
  for (i in 1:nMonths) {
    oStates[[i]] <- aState
    oStates[[i]]$month <- moText[moIdx]
    moIdx <- moIdx+1
  }
  
  return( oStates )
}


# Find the indices where the target string matches elements in the string vector
monthIndex <- function(aMonth, moString) {
  index <- which(moString == aMonth)
  # If the string is not found, return NA
  if (length(index) == 0) {
    return(NA)
  } else {
    return(index)
  }
}




# Fin.