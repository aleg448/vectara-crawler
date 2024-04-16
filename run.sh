#!/bin/bash

if [ -z "$CONFIG_FILE" ]; then
    echo "Error: CONFIG_FILE environment variable is not set"
    exit 1
fi

if [ -z "$PROFILE" ]; then
    echo "Error: PROFILE environment variable is not set"
    exit 2
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: '$CONFIG_FILE' is not a valid configuration file"
    exit 3
fi

# Copy the config folder into the Docker container
mkdir -p ~/tmp/mount
cp -r config ~/tmp/mount/

# Build docker container
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    ARCH="amd64"
fi

# Determine the build command based on the availability of Buildx
function has_buildx() {
    docker buildx version > /dev/null 2>&1
}

if has_buildx; then
    BUILD_CMD="buildx build"
    echo "Building for $ARCH with buildx"
else
    BUILD_CMD="build"
    echo "Building for $ARCH"
fi

sum_tables=`python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['vectara'].get('summarize_tables', 'false'))" | tr '[:upper:]' '[:lower:]'`
mask_pii=`python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['vectara'].get('mask_pii', 'false'))" | tr '[:upper:]' '[:lower:]'`

tag="vectara-ingest"

if [[ "$sum_tables" == "true" || "$mask_pii" == "true" ]]; then
    echo "Building with extra features"
    docker $BUILD_CMD --build-arg INSTALL_EXTRA="true" --platform linux/$ARCH . --tag="$tag:latest"
else
    docker $BUILD_CMD --build-arg INSTALL_EXTRA="false" --platform linux/$ARCH . --tag="$tag:latest"
fi

if [ $? -eq 0 ]; then
    echo "Docker build successful."
else
    echo "Docker build failed. Please check the messages above. Exiting..."
    exit 4
fi

# Remove old container if it exists
docker container inspect vingest &>/dev/null && docker rm -f vingest

# Run docker container
crawler_type=`python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['crawling']['crawler_type'])" | tr '[:upper:]' '[:lower:]'`

if [[ "${crawler_type}" == "folder" ]]; then
    # Special handling of "folder crawler" where we need to mount the folder under /home/vectara/data
    folder=`python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['folder_crawler']['path'])"`
    echo $folder
    docker run -d -v "$folder:/home/vectara/data" -v ~/tmp/mount/config:/home/vectara/config -e CONFIG=/home/vectara/config/$CONFIG_FILE -e PROFILE=$PROFILE -e VECTARA_API_KEY=$VECTARA_API_KEY -e VECTARA_CORPUS_ID=$VECTARA_CORPUS_ID -e VECTARA_CUSTOMER_ID=$VECTARA_CUSTOMER_ID --name vingest $tag
elif [[ "$crawler_type" == "csv" ]]; then
    # Special handling of "csv crawler" where we need to mount the csv file under /home/vectara/data
    csv_path=`python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['csv_crawler']['csv_path'])"`
    docker run -d -v "$csv_path:/home/vectara/data/file.csv" -v ~/tmp/mount/config:/home/vectara/config -e CONFIG=/home/vectara/config/$CONFIG_FILE -e PROFILE=$PROFILE -e VECTARA_API_KEY=$VECTARA_API_KEY -e VECTARA_CORPUS_ID=$VECTARA_CORPUS_ID -e VECTARA_CUSTOMER_ID=$VECTARA_CUSTOMER_ID --name vingest $tag
elif [[ "$crawler_type" == "bulkupload" ]]; then
    # Special handling of "bulkupload crawler" where we need to mount the JSON file under /home/vectara/data
    json_path=`python3 -c "import yaml; print(yaml.safe_load(open('$CONFIG_FILE'))['bulkupload_crawler']['json_path'])"`
    docker run -d -v "$json_path:/home/vectara/data/file.json" -v ~/tmp/mount/config:/home/vectara/config -e CONFIG=/home/vectara/config/$CONFIG_FILE -e PROFILE=$PROFILE -e VECTARA_API_KEY=$VECTARA_API_KEY -e VECTARA_CORPUS_ID=$VECTARA_CORPUS_ID -e VECTARA_CUSTOMER_ID=$VECTARA_CUSTOMER_ID --name vingest $tag
else
    docker run -d -v ~/tmp/mount/config:/home/vectara/config -e CONFIG=/home/vectara/config/$CONFIG_FILE -e PROFILE=$PROFILE -e VECTARA_API_KEY=$VECTARA_API_KEY -e VECTARA_CORPUS_ID=$VECTARA_CORPUS_ID -e VECTARA_CUSTOMER_ID=$VECTARA_CUSTOMER_ID --name vingest $tag
fi

if [ $? -eq 0 ]; then
    echo "Success! Ingest job is running."
    echo "You can try 'docker logs -f vingest' to see the progress."
else
    echo "Ingest container failed to start. Please check the messages above."
fi