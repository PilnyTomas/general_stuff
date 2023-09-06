#!/bin/bash

# Strings to be ignored by sed when modifying $existing_chip to $new_chip
declare -a ignore_strings=("string1" "string2" "anotherString")

# Check if a file contains any of the ignore strings
file_contains_ignore_string() {
    local file="$1"
    for ignore_string in "${ignore_strings[@]}"; do
        if grep -q "$ignore_string" "$file"; then
            return 0
        fi
    done
    return 1
}

# Detailed search and modify function
detailed_search_and_modify() {
    local file="$1"
    local new_file="$2"
    # Modify lines containing the existing_chip but not the ignore strings
    cp "$file" "$new_file"
    for ignore_string in "${ignore_strings[@]}"; do
        sed -i "/$ignore_string/!s/$existing_chip/$new_chip/g" "$new_file"
    done
}

function print_help {
    echo "This script helps add library for new chip based on an existing\
library for another chip."
    echo "This script was written and tested primarily for ESP chips."
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "-e <existing_chip>   Specify the existing chip name."
    echo "-n <new_chip>       Specify the new chip name."
    echo "-d <driver>         Specify the driver name."
    echo "-c [editor]         Specify the editor to compare existing and new
                    file. By default vimdiff."
    echo "-a                  Add new files to git staging area."
    echo "-v                  Enable verbose mode."
    echo "-h                  Display this help message."
    echo
    echo "Example:"
    echo "$0 -e esp32 -d rmt -n esp32s2 -v -a -r nano"
}

verbose=false
add_to_git=false
editor="vimdiff"
show_diff=false

while getopts ":e:n:d:var:h" opt; do
  case $opt in
    e) existing_chip="$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]')" ;;
    n) new_chip="$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]')" ;;
    d) driver="$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]')" ;;
    v) verbose=true ;;
    a) add_to_git=true ;;
    c) editor="$OPTARG"
       show_diff=true ;;
    h) print_help; exit 0 ;;
    \?) echo "Invalid option -$OPTARG" >&2; print_help; exit 1 ;;
  esac
done

# Sanity checks
if [ -z "$existing_chip" ] || [ -z "$new_chip" ] || [ -z "$driver" ]; then
    echo "Error: Missing mandatory parameters!"
    print_help
    exit 1
fi

# Check for valid values or conditions if necessary.
# For instance, ensuring that existing_chip is not the same as new_chip:
if [ "$existing_chip" == "$new_chip" ]; then
    echo "Error: Existing chip and new chip cannot be the same."
    print_help
    exit 1
fi

# Search files with exact matches for existing chip and driver.
drivers=$(find '.' -name "*$driver*")
filtered=$(echo "$drivers" | grep -v "Documents" | grep -v ".git")
file_list=$(echo "$filtered" | grep "/$existing_chip/")

for file in $file_list; do
  [[ $verbose == true ]] && echo -e "\nProcessing file: $file"
  if [ -d "$file" ]; then
    [[ $verbose == true ]] && echo "Skipping directory: $file"
    continue
  fi

  new_file=$(echo "$file" | sed "s/$existing_chip/$new_chip/g")
  [[ $verbose == true ]] && echo "New file path: $new_file"
  # If the new directory doesn't exist
  new_dir=$(dirname "$new_file")
  if [[ ! -d $new_dir ]]; then
    echo "Target directory $new_dir not found!"

    # Provide hints on similar folders
    base_dir=$(dirname "$new_dir")
    if [[ -d $base_dir ]]; then
      similar_dir=$(find "$base_dir" -maxdepth 1 -type d | grep -v "$base_dir$")
      echo "Here are some suggestions from $base_dir:"
      echo "$similar_dir"
      echo "Please provide the correct directory (or press Enter to skip):"
      read -r user_dir

      # If user provides a new directory, use that. Otherwise, continue with the loop.
      if [[ ! -z $user_dir ]]; then
        new_dir=$user_dir
        new_file="$new_dir/$(basename $new_file)"
      else
        continue
      fi
    else
      continue
    fi
  fi

  cp "$file" "$new_file"
  #sed -i "s/$existing_chip/$new_chip/g" "$new_file"
  # Check if the file contains any of the ignore strings
  if file_contains_ignore_string "$file"; then
      detailed_search_and_modify "$file" "$new_file"
  else
      cp "$file" "$new_file"
      sed -i "s/$existing_chip/$new_chip/g" "$new_file"
  fi
  [[ $verbose == true ]] && echo "Copied and modified $file to $new_file"

  if [ "$show_diff" == true ]; then
    $editor $file $new_file
  fi

  if $add_to_git; then
    git add "$new_file"
  fi

done
