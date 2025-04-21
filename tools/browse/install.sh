#!/usr/bin/env bash

bundle_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

export PYTHONPATH=$PYTHONPATH:"$bundle_dir/lib"

# Write default environment variables into the environment storage
#_write_env "AZURE_OPENAI_API_KEY" "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
# SECRET. DON'T MERGET THE COMMIT
#_write_env "AZURE_OPENAI_ENDPOINT" "https://ai-bkannan5197ai619228097268.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-08-01-preview"

# install browser-use
pip install browser-use
playwright install-deps
playwright install
