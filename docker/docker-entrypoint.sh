#!/bin/bash
set -e

if [ ! -d $OUTPUTS_PATH ]; then
    echo "!! WARNING !!: Output directory mount is required but not found at: $OUTPUTS_PATH. Program will likely FAIL! Customise this path with the OUTPUTS_PATH environment variable."
fi

if [ ! -d $RME_PATH ]; then
    echo "!! WARNING !!: RME directory mount is required but not found at: $RME_PATH. Program will likely FAIL! Customise this path with the RME_PATH environment variable."
    echo "IMPORTANT NOTE : This RME must have the reefmod_gbr.gpkg inside /path/to/rme/data_files/region. See step 1 of https://open-aims.github.io/ReefModEngine.jl/v1.4.1/getting_started#Pre-initialization-setup. Step 2 is not required in this image."
fi


# If all checks pass, execute the provided command
exec "$@"
