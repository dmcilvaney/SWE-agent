#!/usr/bin/env bash

bundle_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

export PYTHONPATH=$PYTHONPATH:"$bundle_dir/lib"

# Write default environment variables into the environment storage
_write_env "AZURE_OPENAI_API_KEY" "sk-proxy-fake-key-for-local-use-only"
# SECRET. DON'T MERGET THE COMMIT
_write_env "AZURE_OPENAI_ENDPOINT" "http://127.0.0.1:8000"

# install browser-use
pip install browser-use
playwright install-deps
playwright install
