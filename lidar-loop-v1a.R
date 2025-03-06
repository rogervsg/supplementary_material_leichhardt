######################################################################
#### LIDAR processing workflow - adapted from Poornima Sivanandam ####
#### Author: Rogerio Goncalves #######################################
#### Date: 25/08/2024 ################################################
#### Version: 1a #####################################################
######################################################################



# List of directories for each area, including a name for each area
areas <- list(
  list(name = "add_area_name",
       in_dir = "add_input_dir",
       out_dir = "add_output_dir",
       tmp_dir = "add_temp_dir")
)

# Loop through each area and apply the workflow
for (area in areas) {
  
  # Update input and output directories for the current area
  name <- area$name
  in_dir <- area$in_dir
  out_dir <- area$out_dir
  tmp_dir <- area$tmp_dir
  
  gnd_dir <- paste(file.path(tmp_dir),"01_csf_gnd\\", sep="")
  norm_dir <- paste(file.path(tmp_dir), "02_ht_norm\\", sep="")
  chm_dtm_dir <- paste(file.path(tmp_dir), "03_chm_dtm\\", sep="")
  metrics_dir <- paste(file.path(tmp_dir), "04_metrics\\", sep="")
  
  # Create output directories if they do not exist
  dir.create(out_dir, showWarnings = FALSE)
  dir.create(tmp_dir, showWarnings = FALSE)
  dir.create(gnd_dir, showWarnings = FALSE)
  dir.create(norm_dir, showWarnings = FALSE)
  dir.create(chm_dtm_dir, showWarnings = FALSE)
  dir.create(metrics_dir, showWarnings = FALSE)
  
  # Create LASCatalog
  ctg <- readLAScatalog(in_dir)
  
  # Create lax files for spatial indexing if not done already
  if(length(list.files(path = in_dir, pattern = "\\.lax$")) == 0) {
    lidR:::catalog_laxindex(ctg)
  }
  
  # Ground classification
  mycsf <- csf(sloop_smooth=FALSE, cloth_resolution = 0.2, iterations = 500, class_threshold = 0.1)
  opt_output_files(ctg) <- paste(gnd_dir, paste0(name, "_csf_gnd_{ID}"))
  opt_chunk_size(ctg) <- 100
  opt_chunk_buffer(ctg) <- 10 
  opt_progress(ctg) <-FALSE
  
  ctg_gnd_classified <- classify_ground(ctg, mycsf, last_returns = FALSE)
  lidR:::catalog_laxindex(ctg_gnd_classified)
  
  # Write ground classified las
  ctg <- readLAScatalog(gnd_dir)
  las <- readLAS(ctg)
  writeLAS(las, file.path(out_dir, paste0(name, "_gnd_classified.laz")))
  
  # Generate DTM
  opt_output_files(ctg_gnd_classified) <- paste(chm_dtm_dir, paste0(name, "_dtm_idw_{ID}"), sep="")
  opt_progress(ctg_gnd_classified) <-FALSE
  dtm_raster <- rasterize_terrain(ctg_gnd_classified, res=0.05, algorithm = knnidw(k = 10L, p = 2))
  writeRaster(dtm_raster, file.path(out_dir, paste0(name, "_dtm_raster_05.tif")), filetype="GTiff")
  
  # Hillshade plot
  dtm_prod <- terrain(dtm_raster, v = c("slope", "aspect"), unit = "radians")
  dtm_hillshade <- shade(slope = dtm_prod$slope, aspect = dtm_prod$aspect)
  plot(dtm_hillshade, col = gray(0:30/30), legend = FALSE)
  
  # 3D plot
  plot_dtm3d(dtm_raster)
  
  # Normalise point cloud
  opt_output_files(ctg_gnd_classified) <- paste(norm_dir, paste0(name, "_ht_norm_{ID}"), sep="")
  opt_merge(ctg_gnd_classified) <- TRUE 
  plot(ctg_gnd_classified, chunk = TRUE)
  
  ctg_norm <- normalize_height(ctg_gnd_classified, knnidw(k=10, p=2))
  lidR:::catalog_laxindex(ctg_norm)
  
  # Canopy Height Model
  opt_merge(ctg_norm) <- TRUE 
  opt_output_files(ctg_norm) <- paste(chm_dtm_dir, paste0(name, "_chm_{ID}"), sep="")
  opt_progress(ctg_norm) <-FALSE
  plot(ctg_norm, chunk = TRUE)
  
  chm_p2r_ctg <- rasterize_canopy(ctg_norm, res=0.05, p2r(0.2))
  plot(chm_p2r_ctg, col = viridis(10))
  writeRaster(chm_p2r_ctg, file.path(out_dir, paste0(name, "_chm_p2r20_05.tif")), filetype="GTiff")
  
  # Canopy Cover
  canopyCover <- function(z, rn) {
    first <- rn == 1L
    zfirst <- z[first]
    num_first_rtns <- length(zfirst)
    first_above_thres <- sum(zfirst > 1.4)
    x <- (first_above_thres / num_first_rtns)
    return(x)
  }
  opt_output_files(ctg_norm) <- paste(chm_dtm_dir, paste0(name, "_ccov_{ID}"), sep="")
  canopy_cover <- pixel_metrics(ctg_norm, ~canopyCover(Z, rn=ReturnNumber), res = 1)
  plot(canopy_cover, col = viridis(20))
  writeRaster(canopy_cover, file.path(out_dir, paste0(name, "_canopy_cover_1m.tif")), filetype="GTiff")
  
  # Canopy Density
  canopyDensity <- function(z) {
    num_rtns <- length(z)
    num_above_thres <- sum(z > 1.4)
    x <- (num_above_thres / num_rtns)
    return(x)
  }
  opt_output_files(ctg_norm) <- paste(chm_dtm_dir, paste0(name, "_cdns_{ID}"), sep="")
  canopy_dns <- pixel_metrics(ctg_norm, ~canopyDensity(Z), res = 1)
  plot(canopy_dns, col = viridis(20))
  writeRaster(canopy_dns, file.path(out_dir, paste0(name, "_canopy_dns_1m.tif")), filetype="GTiff")
  
  # Grid metrics
  opt_select(ctg_norm) <- "z"
  opt_filter(ctg_norm) <- "-drop_z_below 0"
  opt_output_files(ctg_norm) <- paste(metrics_dir, paste0(name, "_metrics_{ID}"), sep="")
  
  std_metrics_raster <- pixel_metrics(ctg_norm, .stdmetrics_z, res = 1)
  
  # Save the standard metrics raster
  terra::writeRaster(std_metrics_raster, file.path(out_dir, paste0(name, "_pixel_std_metrics_1m.tiff")), 
                     filetype = "GTiff", overwrite = TRUE)
  
  # Plot some metrics
  plot(std_metrics_raster)
}

# End of loop
