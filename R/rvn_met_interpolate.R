#' @title Spatially Interpolate meteorological data
#'
#' @description
#' rvn_met_spatial_interpolation interpolates/infills missing meteorological data by
#' using an inverse-distance weighting scheme to infill using data from nearby
#' meteorological stations.
#'
#' @details
#' This function takes a meteorological data set with multiple station data in one data frame and
#' interpolates the missing values for key stations, for the specified meteorological variables to interpolate.
#'
#' The format of the weather_data input is consistent with that from the weathercan::weather_dl function, which
#' is the recommended tool to gather this input (see the examples).
#'
#' This function does not guarantee to infill all missing values, since this depends on the availability of data
#' at other locations when it lacks at a given station, although a warning is issued if
#' missing values remain following the interpolation. It may be possible to infill missing
#' values through repeated uses of this function, although the information will be less robust and
#' more reliant on fewer stations with repeated calls of this function.
#'
#' This function does not (currently) perform checks for the quality of the supplied or infilled data,
#' such as checking for maximum temperature less than minimum temperature, unreasonable precipitation values, etc.
#'
#' The key_stn_ids indicates which stations should have their missing values interpolated. It is likely that
#' the user will require more data to perform a proper interpolation than the user cares to have gauge
#' records at, i.e. some stations are only provided for the purposes of infilling missing data at other stations.
#' Since the interpolation of all stations provided can become computationally expensive, the user can
#' specify which stations they want to interpolate data for with the key_stn_ids parameter. Station IDs that
#' are not within the key_stn_ids (if not NULL) will still be used, but not themselves infilled.
#'
#' The distance calculation, estimating the distance between stations, is performed by converting the lat/long into
#' UTM coordinates within the specified projection ID. The projection ID should be supplied as the local projection
#' system that is most appropriate for the given stations, as the default will not be appropriate outside of the
#' UTM 17N system, and may skew the interpolation results.
#'
#' @param weather_data data frame of input meteorological data from multiple stations
#' @param cc columns from weather_data to infill missing values in
#' @param key_stn_ids station IDs in which to perform the interpolation
#' @param projID the spatial projection ID in which to perform the distance calculation (default 26917=UTM 17N)
#' @param ppexp exponent to use in inverse distance weighting calculation (default 2)
#'
#' @return \item{new_wd}{infilled meteorological data set}
#'
#' @examples
#'
#' \dontrun{
#'
#' # example to create infilled data sets
#'
#' library(weathercan)
#' stn <- weathercan::stations_search(name="Glen allan", interval = "day")
#' dl_stn <- stn
#' all_stns <- weathercan::stations_search(coords=c(stn$lat, stn$lon), dist=40,
#'           interval="day", starts_latest = 2002,
#'           ends_earliest = 2010)
#'
#' weather_data <- weather_dl(station_ids = all_stns$station_id, start = "2002-10-01", interval="day")
#' dl_stn <- all_stns[c(1,3,4,6,7),]
#'
#' new_wd <- rvn_met_spatial_interpolation(weather_data = weather_data, key_stn_ids = dl_stn$station_id)
#'
#' new_wd[new_wd$station_name == "GLEN ALLAN" & is.na(new_wd$total_precip),]
#' new_wd[new_wd$station_name == "GLEN ALLAN" & is.na(new_wd$max_temp),]
#' new_wd[new_wd$station_name == "GLEN ALLAN" & is.na(new_wd$min_temp),]
#'
#' new_wd[new_wd$station_name == "STRATFORD WWTP" & is.na(new_wd$total_precip),]
#' new_wd[new_wd$station_name == "STRATFORD WWTP" & is.na(new_wd$max_temp),]
#' new_wd[new_wd$station_name == "STRATFORD WWTP" & is.na(new_wd$min_temp),]
#'
#' # some missing values still exist - could re-run the script to infill these values again
#' new_wd2 <- rvn_met_spatial_interpolation(weather_data = new_wd, key_stn_ids = dl_stn$station_id)
#' }
#'
#' @export rvn_met_spatial_interpolation
#' @importFrom sp CRS proj4string spTransform
#' @import RavenR
rvn_met_spatial_interpolation <- function(weather_data=NULL,
                                cc=c("max_temp","min_temp","total_precip"),
                                key_stn_ids=NULL,
                                projID=26917,
                                ppexp=2) {

  wd <- weather_data

  # transform coordinates of all stations
  res <- data.frame(ID = wd$station_id, X = wd$lon, Y = wd$lat)
  sp::coordinates(res) <- c("X", "Y")
  sp::proj4string(res) <- sp::CRS("+proj=longlat +datum=WGS84")
  res <- spTransform(res, sp::CRS(sprintf("+init=epsg:%i",projID)))
  myprojstring = sp::CRS(sprintf("+init=epsg:%i",projID))

  wd[, c("X_reproj", "Y_reproj")] <- res@coords

  # new wd - subset of keystns
  if (is.null(key_stn_ids)) {
    new_wd <- weather_data
  } else {
    new_wd <- weather_data[weather_data$station_id %in% key_stn_ids,]
  }

  # main interpolation loop
  for (item in cc) {

    for (i in 1:nrow(new_wd)) {

      if (is.na(new_wd[i,item])) {

        currentdate <- new_wd$date[i]

        # temp <- wd[which(wd$date == currentdate),]
        temp <- wd[which(wd$date == currentdate & !(is.na(wd[,item]))),]

        if (nrow(temp) == 0) {
          warning("missing data for %s, more stations may be required: ", currentdate)
        } else if (nrow(temp) == 1) {
          new_wd[i, item] <- temp[1, item]
        } else {

          temp$dists <- sqrt( (temp$X_reproj - wd$X_reproj[i])^2 + (temp$Y_reproj - wd$Y_reproj[i])^2  )

          numer <- 0
          denom <- 0

          for (j in 1:nrow(temp)) {
            numer <- numer + temp[j, item]/(temp[j, "dists"]^ppexp)
            denom <- denom + 1/(temp[j, "dists"]^ppexp)
          }

          new_wd[i, item] <- numer/denom
        }

      }
    }
  }

  # any(is.na(new_wd[,cc]))

  # add checks for max_temp < min_temp, etc

  return(new_wd)
}

