#!/bin/bash

set -x

# This script is used to run the SWE agent with a specific configuration.

# It will prep a working directory by using a docker container to install a SRPM and run rpmbuild -bp to
# prepare the source directory for the SRPM. This folder will be mounted into the container, so that is can
# be used by SWE agent later.

# Once the sources are prepared, the script will initialize a git repository in the source directory and
# create a commit with the sources. This commit will be used as the base for the SWE agent to work on.

# A summary of the CVE will also be generated and saved in the directory.

# The layout of the output directory that will be passed to the SWE agent is as follows:
# .
# ├── inputs
# │   ├── <CVE summary>.txt
# │   ├── <CVE>.patch
# ├── workingdir
# │   ├── <SRPM name>
# │   │   ├── <prepared sources>

# Example usage:
# ./run.sh tcpdump CVE-2020-8037 /path/to/input.patch /path/to/working/dir mcr.microsoft.com/cbl-mariner/base/core:2.0 [/host/path/to/working/dir]
#
# When running inside a dev container, you may need to specify the host_output_dir parameter
# to ensure Docker mounts work correctly.

package_name=$1
cve_id=$2
input_patch_src_dir=$3
output_dir=$4
mariner_image=$5
host_output_dir=$6  # Optional: host path that corresponds to output_dir when in a dev container
tools_image="localhost/mariner/srpm-prep"

script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Make abs path for docker
output_dir=$(realpath "$output_dir")

# Handle Docker-in-Docker scenario (like VS Code dev container)
if [ -f "/.dockerenv" ]; then
    echo "Running in a container environment (Docker-in-Docker)"

    # If no host_output_dir was provided, try to infer it or warn user
    if [ -z "$host_output_dir" ]; then
        echo "ERROR: Running in a container but no host_output_dir provided."
        echo "Please provide the host path that corresponds to the output_dir ($output_dir) when running in a dev container."

        exit 1
    else
        HOST_OUTPUT_DIR="$host_output_dir"
        echo "Using provided host_output_dir: $HOST_OUTPUT_DIR"

        # Verify the mapping by creating a test file and checking if it appears
        TEST_FILE="docker_mount_test_$(date +%s).txt"
        echo "Creating test file to verify Docker mount mapping..."
        echo "test content" > "$output_dir/$TEST_FILE"

        # Run a simple Docker container to check if the file is visible
        VALIDATION_RESULT=$(docker run --rm -v "$HOST_OUTPUT_DIR:/test_mount" alpine sh -c "if [ -f '/test_mount/$TEST_FILE' ]; then echo 'SUCCESS'; else echo 'FAILURE'; fi")

        # Check validation result
        if [ "$VALIDATION_RESULT" = "SUCCESS" ]; then
            echo "✅ Host path mapping validated successfully!"
        else
            echo "❌ ERROR: Host path mapping validation failed!"
            echo "The host_output_dir ($HOST_OUTPUT_DIR) does not correctly map to output_dir ($output_dir)."
            echo "Please provide the correct host path that corresponds to: $output_dir"
            rm -f "$output_dir/$TEST_FILE"
            exit 1
        fi

        # Cleanup test file
        rm -f "$output_dir/$TEST_FILE"
    fi
else
    # Not in a container, use the path as is
    HOST_OUTPUT_DIR="$output_dir"
    echo "Running directly on host, using output_dir: $output_dir"
fi

cve_finder_tool="$script_dir/cve_finder.py"

# Resolve SRPM version string from srpm_names.json
srpm_version=$(jq -r --arg pkg "$package_name" --arg cve "$cve_id" \
  '.[$pkg + "/" + $cve]' "$script_dir/srpm_names.json")

if [[ -z "$srpm_version" || "$srpm_version" == "null" || "$srpm_version" == "unknown" ]]; then
  echo "ERROR: SRPM for $package_name/$cve_id not found in srpm_names.json" >&2
  exit 1
fi
srpm_filename="${srpm_version}.src.rpm"
echo "Resolved SRPM: $srpm_filename"

# Clean up the output directory if it exists, then create it
rm -rf "$output_dir"
mkdir -p "$output_dir"
mkdir -p "$output_dir/inputs"
mkdir -p "$output_dir/workingdir"



# Make sure output directory has appropriate permissions
chmod -R 777 "$output_dir"

input_patch_path="$input_patch_src_dir/$package_name/$cve_id/upstream.patch"
if [ ! -f "$input_patch_path" ]; then
  echo "ERROR: Input patch file not found: $input_patch_path" >&2
  exit 1
fi

# Add the input files to the inputs directory
cp "$input_patch_path" "$output_dir/inputs/"
# (note: SRPM will be downloaded inside the container)

# Run the cve_finder.py script to generate a summary of the CVE
echo "Generating CVE summary..."
python3 "$cve_finder_tool" "$cve_id" "$output_dir/inputs/info.txt"

# Run the docker container to prepare the sources
echo "Preparing sources..."

# Build helper image once (if missing / outdated)
if ! docker image inspect "$tools_image" >/dev/null 2>&1; then
  echo "Building helper image $tools_image ..."
  docker build -t "$tools_image" \
               --build-arg BASE_IMAGE="$mariner_image" \
               -f "$script_dir/Dockerfile.srpmfinder" "$script_dir"
fi

echo "mounting $HOST_OUTPUT_DIR to /mnt in $tools_image"

# Get current user ID and group ID to match file ownership
USER_ID=$(id -u)
GROUP_ID=$(id -g)

docker run --rm -e SRPM_FILENAME="$srpm_filename" -e SRPM_VERSION="$srpm_version" \
  -v "$HOST_OUTPUT_DIR:/mnt" "$tools_image" /bin/bash -e -c "
  set -x

  # Download SRPM to shared volume
  dnf download --destdir /mnt/inputs --source \"\$SRPM_VERSION\" >/dev/null

  # Install the build dependencies for the SRPM so we can run prep
  dnf builddep -y /mnt/inputs/\"\$SRPM_FILENAME\" >/dev/null

  # Extract SRPM into custom _topdir
  rpm --define '_topdir /mnt/workingdir' -ihv /mnt/inputs/\"\$SRPM_FILENAME\" >/dev/null

  # Prepare sources
  rpmbuild -bp --noclean --nodeps --define '_topdir /mnt/workingdir' --define 'with_check 0' /mnt/workingdir/SPECS/*.spec

  # Ensure correct permissions on output files
  chown -R $USER_ID:$GROUP_ID /mnt/
"

# Prepare the swe-agent working directory
echo "Preparing SWE agent working directory..."
tempdir=$(mktemp -d)
sweagent_dir="$HOST_OUTPUT_DIR/sweagent"
echo "Temporary directory: $tempdir"

mkdir -p "$sweagent_dir"
mkdir -p "$sweagent_dir/backport"

# Copy the relevant files to the SWE agent working directory, then git init and commit them.
# First grab the directory from the BUILD folder (this is the one that was built by rpmbuild -bp)
# Use find to get the actual build directory inside BUILD, excluding BUILD itself
dir_name=$(find "$output_dir/workingdir/BUILD" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "$dir_name" ]; then
  echo "ERROR: No build directory found in $output_dir/workingdir/BUILD"
  exit 1
fi

echo "Found directory: $dir_name"
cp -r "$dir_name"/* "$sweagent_dir"

# Add the upstream patch and info files
cp "$input_patch_path" "$sweagent_dir/SWE-agent_upstream.patch"
cp "$output_dir/inputs/info.txt" "$sweagent_dir/SWE-agent_info.txt"

# Initialize a git repository in the working directory before we add the extra files
(
  cd "$sweagent_dir"
  git init
  git branch -m current_code
  git config user.name "SWE-CVE-Bot"
  git config user.email "swe_cve_bot@microsoft.com"
  git add .
  git commit -m "Initial commit with sources for $cve_id"
)

# Add the upstream patch and info files
cp "$input_patch_path" "$sweagent_dir/SWE-agent_upstream.patch"
cp "$output_dir/inputs/info.txt" "$sweagent_dir/SWE-agent_info.txt"
# Add the patch and info as an additional commit
(
  cd "$sweagent_dir"
  git add SWE-agent_upstream.patch SWE-agent_info.txt
  git commit -m "TEMPORARY: Add upstream patch and info for $cve_id"
)

sweagent run \
  --config config/patch_backporter.yaml \
  --env.repo.type=local \
  --env.repo.path="$sweagent_dir" \
  --problem_statement.text='backport SWE-agent_upstream.patch and place the result in the backport folder.' \
  --agent.model.name=azure/gpt-4o \
  --agent.model.api_base='http://127.0.0.1:8000'
