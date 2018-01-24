#!/usr/bin/env bash

# This script run dbv_deploy.py

script_path="${BASH_SOURCE[0]}"
current_path="$(cd "$(dirname "${script_path}")" ; pwd)"
echo "Script path: ${current_path}/$(basename "${script_path}")"

python "${current_path}/$(basename "dbv_deploy.py")"
