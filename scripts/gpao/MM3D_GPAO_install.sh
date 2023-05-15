#!/bin/bash

pip install ign-gpao-project-builder

MMGPAO_path=/Volumes/ESPACE_TRAVAIL_Puma/DANI/RUBEN/MM3D/micmac/scripts/gpao

lines_to_add=(
    " "
    "# MicMac GPAO "
    "source $MMGPAO_path/MMGPAO_env.sh"
)

bash_profile_path=$HOME/.bash_profile

source $MMGPAO_path/MMGPAO_env.sh

# Check if the Bash profile file exists
if [ -f "$bash_profile_path" ]; then
  # Append lines to the file
  for line in "${lines_to_add[@]}"; do
    echo "$line" >> "$bash_profile_path"
  done
  echo "Added GPAO env setup in $bash_profile_path. MicMac GPAO is ready to use."
else
  echo "Bash profile file not found."
fi
