#!/usr/bin/env bash
set -eo pipefail

# Create mount directory for service
mkdir -p $MNT_DIR

echo "Mounting GCS Fuse."
gcsfuse --debug_gcs --debug_fuse $BUCKET $MNT_DIR
echo "Mounting completed."

# Start the application
nginx
./strfry relay
# Exit immediately when one of the background processes terminate.
wait -n
# [END cloudrun_fuse_script]