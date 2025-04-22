#!/bin/bash

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
# ./run.sh CVE-2023-12345 /path/to/input.srpm /path/to/input.patch /path/to/working/dir mcr.microsoft.com/cbl-mariner/base/core:2.0

cve_id=$1
input_srpm_path=$2
input_patch_path=$3
output_dir=$4
mariner_image=$5

script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cve_finder_tool="$script_dir/cve_finder.py"

# Clean up the output directory if it exists, then create it
rm -rf "$output_dir"
mkdir -p "$output_dir"
mkdir -p "$output_dir/inputs"
mkdir -p "$output_dir/workingdir"

# Add the input files to the inputs directory
cp "$input_srpm_path" "$output_dir/inputs/"
cp "$input_patch_path" "$output_dir/inputs/"

# Run the cve_finder.py script to generate a summary of the CVE
echo "Generating CVE summary..."
python3 "$cve_finder_tool" "$cve_id" "$output_dir/inputs/$cve_id.txt"

# Run the docker container to prepare the sources
echo "Preparing sources..."
docker run --rm -v "$output_dir:/mnt" "$mariner_image" /bin/bash -c "cd /mnt/workingdir && rpmbuild -bp --define '_topdir /mnt/workingdir' /mnt/inputs/$input_srpm_path"

# DEBUG: omit for now
#sweagent run --env.repo.github_url=https://github.com/SWE-agent/test-repo --problem_statement.github_url=https://github.com/SWE-agent/test-repo/issues/1 --agent.model.name=azure/gpt-4o --agent.model.api_base='http://127.0.0.1:8000'
