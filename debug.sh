#!/bin/bash

set -ex

host_path='/home/damcilva/SWE-agent/temp/work'
local_path='/workspaces/SWE-agent/temp/work'

echo Nothing!
ls -laR $local_path

echo 'No mounts -> still nothing'
docker run -it --rm -e SRPM_FILENAME=python-cryptography-3.3.2-3.cm2.src.rpm -e SRPM_VERSION=python-cryptography-3.3.2-3.cm2 localhost/mariner/srpm-prep ls -laR /mnt

echo 'Mounts -> Full of FILES???'
docker run -it --rm -e SRPM_FILENAME=python-cryptography-3.3.2-3.cm2.src.rpm -e SRPM_VERSION=python-cryptography-3.3.2-3.cm2 -v $host_path:/mnt localhost/mariner/srpm-prep bash -c "ls -laR /mnt" | head -n 30

echo Nothing!
ls -laR $local_path
