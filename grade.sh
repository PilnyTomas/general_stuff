#!/bin/bash
# This script will take a file with error message from idf.py in first argument ($1) and installs required version (downgrades if needed)
# The error message is complaining about python package mismatch similar to the following:
# pyparsing>=2.0.3,<2.4.0
# kconfiglib==13.7.1
#
# To run this script get error message:
# idf.py 2> err
# Then run this script:
# grade.sh err

# Parse the error message file provided as an argument
if [ $# -ne 1 ]; then
  echo "Usage: $0 <error message file>"
  exit 1
fi

error_file=$1

# Check if the error message contains package requirements
if grep -q 'The following .* requirements are not satisfied' "$error_file"; then
  # Extract the package requirements from the error message
  packages=$(grep 'The following .* requirements are not satisfied' "$error_file" | sed 's/.*The following \(.*\) requirements are not satisfied:.*/\1/')

  # Loop through each package requirement and install, upgrade, or downgrade as necessary
  for package in $packages; do
    # Extract the package name and version requirements
    name=$(echo "$package" | awk -F '==' '{print $1}')
    version=$(echo "$package" | awk -F '==' '{print $2}')
    op=$(echo "$version" | sed -e 's/[0-9]*\.[0-9]*\.[0-9]*\([a-zA-Z]*\).*/\1/')

    # Install, upgrade, or downgrade the package based on the version requirements
    if [ "$op" == "" ] || [ "$op" == "=" ]; then
      echo "Installing package $name==$version"
      pip install "$name==$version"
    elif [ "$op" == ">" ]; then
      echo "Upgrading package $name to $version"
      pip install --upgrade "$name==$version"
    elif [ "$op" == "<" ]; then
      echo "Downgrading package $name to $version"
      pip install "$name==$version" --force-reinstall
    else
      echo "Invalid version requirement $version for package $name"
    fi
  done

  # Run the installation script provided in the error message
  install_script=$(grep 'To install the missing packages, please run' "$error_file" | sed 's/.*To install the missing packages, please run "\(.*\)".*/\1/')
  echo "Running installation script: $install_script"
  bash "$install_script"
else
  echo "Error: no package requirements found in error message file"
  exit 1
fi
