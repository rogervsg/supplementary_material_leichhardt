import Metashape
import os

# Checking compatibility
compatible_major_version = "2.1"
found_major_version = ".".join(Metashape.app.version.split('.')[:2])
if found_major_version != compatible_major_version:
    raise Exception("Incompatible Metashape version: {} != {}".format(found_major_version, compatible_major_version))

def find_files(folder, types):
    return [entry.path for entry in os.scandir(folder) if (entry.is_file() and os.path.splitext(entry.name)[1].lower() in types)]

def process_area(image_folder, output_folder, min_pitch=-0.2, max_pitch=0.2):
    photos = find_files(image_folder, [".jpg", ".jpeg", ".tif", ".tiff"])

    doc = Metashape.Document()
    doc.save(output_folder + '/project.psx')

    chunk = doc.addChunk()
    chunk.addPhotos(photos)
    doc.save()

    print(str(len(chunk.cameras)) + " images loaded from " + image_folder)

    # Apply min_pitch and max_pitch to filter out cameras with undesired pitch angles
    filtered_cameras = []
    for camera in chunk.cameras:
        if camera.reference.rotation:  # Ensure the rotation data is available
            pitch = camera.reference.rotation[1]  # Access the pitch angle from the rotation vector
            if min_pitch <= pitch <= max_pitch:
                filtered_cameras.append(camera)

    if not filtered_cameras:
        print("No cameras met the pitch criteria; aborting processing.")
        return

    # Disable cameras that do not meet the pitch criteria
    for camera in chunk.cameras:
        if camera not in filtered_cameras:
            camera.enabled = False

    print(f"Filtered out {len(chunk.cameras) - len(filtered_cameras)} images based on pitch criteria")

    chunk.matchPhotos(keypoint_limit=100000, tiepoint_limit=60000, generic_preselection=True, reference_preselection=True)
    doc.save()

    chunk.alignCameras()
    doc.save()

    if not chunk.point_cloud:
        print("Alignment failed; no tie points generated.")
        return

    chunk.buildDepthMaps(downscale=4, filter_mode=Metashape.AggressiveFiltering)
    doc.save()

    chunk.buildDenseCloud()
    doc.save()

    chunk.buildDem(source_data=Metashape.DenseCloudData)
    doc.save()

    chunk.buildOrthomosaic(surface_data=Metashape.DenseCloudData)
    doc.save()

    # Export results
    chunk.exportReport(output_folder + '/report.pdf')
    chunk.exportRaster(output_folder + '/dem.tif', source_data=Metashape.ElevationData)
    chunk.exportRaster(output_folder + '/orthomosaic.tif', source_data=Metashape.OrthomosaicData)

    print('Processing finished for ' + image_folder + ', results saved to ' + output_folder + '.')

# Prompt for the base image folder
base_image_folder = Metashape.app.getExistingDirectory("Select the base image folder:")

# Prompt for the base output folder
base_output_folder = Metashape.app.getExistingDirectory("Select the base output folder:")

# Loop through each subfolder in the base image folder
for folder_name in os.listdir(base_image_folder):
    image_folder = os.path.join(base_image_folder, folder_name)
    if os.path.isdir(image_folder):
        output_path = os.path.join(base_output_folder, folder_name)
        os.makedirs(output_path, exist_ok=True)
        process_area(image_folder, output_path, min_pitch=-0.2, max_pitch=0.2)

print("All areas processed.")
