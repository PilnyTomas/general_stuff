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

# for file in $file_list; do
#   [[ $verbose == true ]] && echo -e "\nProcessing file: $file"
#   if [ -d "$file" ]; then
#     [[ $verbose == true ]] && echo "Skipping directory: $file"
#     continue
#   fi

#   new_file=$(echo "$file" | sed "s/$existing_chip/$new_chip/g")
#   [[ $verbose == true ]] && echo "New file path: $new_file"
#   # If the new directory doesn't exist
#   new_dir=$(dirname "$new_file")
#   if [[ ! -d $new_dir ]]; then
#     echo "Target directory $new_dir not found!"

#     # Provide hints on similar folders
#     base_dir=$(dirname "$new_dir")
#     if [[ -d $base_dir ]]; then
#       similar_dir=$(find "$base_dir" -maxdepth 1 -type d | grep -v "$base_dir$")
#       echo "Here are some suggestions from $base_dir:"
#       echo "$similar_dir"
#       echo "Please provide the correct directory (or press Enter to skip):"
#       read -r user_dir

#       # If user provides a new directory, use that. Otherwise, continue with the loop.
#       if [[ ! -z $user_dir ]]; then
#         new_dir=$user_dir
#         new_file="$new_dir/$(basename $new_file)"
#       else
#         continue
#       fi
#     else
#       continue
#     fi
#   fi

#   cp "$file" "$new_file"
#   #sed -i "s/$existing_chip/$new_chip/g" "$new_file"
#   # Check if the file contains any of the ignore strings
#   if file_contains_ignore_string "$file"; then
#       detailed_search_and_modify "$file" "$new_file"
#   else
#       cp "$file" "$new_file"
#       sed -i "s/$existing_chip/$new_chip/g" "$new_file"
#   fi
#   [[ $verbose == true ]] && echo "Copied and modified $file to $new_file"

#   if [ "$show_diff" == true ]; then
#     $editor $file $new_file
#   fi

#   if $add_to_git; then
#     git add "$new_file"
#   fi

# done


# Modify existing files:

# Modifying the "$new_chip/Make.defs" file

temp_file="temp_makefile"
# Ensure temporary file is empty
> $temp_file

make_defs_file=$(find . -type f -name "Make.defs" | grep "$new_chip/Make.defs")
[[ $verbose == true ]] && echo -e "\nProcessing file: $make_defs_file"
cp $make_defs_file $make_defs_file.backup

if [[ -n $make_defs_file ]]; then
    new_chip_capital=$(echo "$new_chip" | tr '[:lower:]' '[:upper:]')
    driver_capital=$(echo "$driver" | tr '[:lower:]' '[:upper:]')
    insertion_block="ifeq (\$(CONFIG_${new_chip_capital}_${driver_capital}),y)
CHIP_CSRCS += ${new_chip}_${driver}.c
endif
"
    [[ $verbose == true ]] && echo -e "add block:\n$insertion_block"

    inserted=false

    while IFS= read -r line; do
         if [[ "$line" =~ ^[[:space:]]*#ifeq\ \(\$\(CONFIG_ ]]; then
            [[ $verbose == true ]] && echo -e "Line: $line"
            # Extract the key and check if our key should be inserted before it
#            key=$(echo "$line" | sed -n 's/^[[:space:]]*#ifeq (\(\$\(CONFIG_\)\([^,]*\)\),y).*$/\2/p')
            #key=$(echo "$line" | sed -n 's/^[[:blank:]]*#ifeq (\(\$\(CONFIG_\)\([^,]*\)\),y).*$/\3/p')
            #key=$(grep -o -P '(?<=Here).*(?=string)')
            before="#ifeq \(\$\(CONFIG_" # Match ifeq ($(CONFIG_
            after="\),y\)" # Match ),y)
            key=$(grep -o -P '(?<=$before).*(?=$after)')

            [[ $verbose == true ]] && echo -e "Got key: $key"
            if [[ "${new_chip_capital}_${driver_capital}" < "$key" && "$inserted" = false ]]; then
                [[ $verbose == true ]] && echo -e "\nInserting block before line: $line"
                echo "$insertion_block" >> "$temp_file"
                inserted=true
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$make_defs_file"

    # If by the end of the file the block hasn't been inserted, insert it at the end
    if [[ "$inserted" = false ]]; then
        echo "Shit's fucked!"
        #echo "$insertion_block" >> "$temp_file"
    fi
else
    #echo "Make.defs file not found for $new_chip"
    echo "foo"
fi

if [ "$show_diff" = true ]; then
  $editor $make_defs_file.backup $make_defs_file
fi

if $add_to_git; then
  git add "$make_defs_file"
fi

rm $make_defs_file.backup
