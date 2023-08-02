#!/bin/bash
# Bash Menu Script Example
ARDUINO='/home/pilnyt/Arduino/hardware/espressif/esp32'
#ARDUINO2='/home/.arduino15/packages/esp32/hardware/esp32/'
DOT_ARDUINO='/home/pilnyt/.arduino15/packages/esp32/hardware/esp32' # This is where the arduino-esp32 is normally installed and this what arduino-cli is using
mapfile -t subfolders < <(find "$DOT_ARDUINO")
FULL_DOT_ARDUINO_PATH=${subfolders[1]}
IDF_COMPONENT='/home/pilnyt/esp/esp-idf/components/arduino-esp32'
CURRENT_ARD=$(ls -la ~/Arduino/hardware/espressif/ | grep '/home/pilnyt' | sed 's/^.*\///')
CURRENT_IDF=$(ls -la $IDF_COMPONENT | grep '/home/pilnyt' | sed 's/^.*\///')
echo "Current Arduino link: ${CURRENT_ARD}"
echo "Current IDF link: ${CURRENT_IDF}"


options=("Main fork" "Secondary fork" "3rd fork" "4th fork" "5th fork" "Espressif repo for PRs" "Main Espressif repo" "5.1 Espressif repo" "Cancel - keep \"$CURRENT_ARD\"")

if [ -z "$1" ]; then
  # If no argument is provided, prompt the user to choose an option
  PS3="Select an option: "
  select opt in "${options[@]}"
  do
    if [ -n "$opt" ]; then
      break
    else
      echo "Invalid option. Please try again."
    fi
  done
else
  # If an argument is provided, check if it is a valid option number
  selected_option=$(( $1 - 1 ))
  if [ $selected_option -ge 0 ] && [ $selected_option -lt ${#options[@]} ]; then
    opt="${options[selected_option]}"
  else
    echo "Invalid option number. Please provide a valid number from 1 to ${#options[@]}."
    exit 1
  fi
fi

change_link () {
  rm $ARDUINO
  rm $IDF_COMPONENT
  rm $FULL_DOT_ARDUINO_PATH
  ln -s $1 $ARDUINO
  ln -s $1 $IDF_COMPONENT
  ln -s $1 $FULL_DOT_ARDUINO_PATH
}

case $opt in
    "Main fork")
        echo "Switching to main fork"
        change_link "/home/pilnyt/arduino-esp32-fork"
        ;;
    "Secondary fork")
        echo "Switching to secondary fork"
        change_link "/home/pilnyt/arduino-esp32-fork2"
        ;;
    "3rd fork")
        echo "Switching to 3rd fork"
        change_link "/home/pilnyt/arduino-esp32-fork3"
        ;;
    "4th fork")
        echo "Switching to 4th fork"
        change_link "/home/pilnyt/arduino-esp32-fork4"
        ;;
    "5th fork")
        echo "Switching to 5th fork"
        change_link "/home/pilnyt/arduino-esp32-fork5"
        ;;
    "Espressif repo for PRs")
        echo "Switching to main espressif repo for PRs"
        change_link "/home/pilnyt/arduino-esp32-pr"
        ;;
    "Main Espressif repo")
        echo "Switching to main espressif repo"
        change_link "/home/pilnyt/arduino-esp32"
        ;;
    "5.1 Espressif repo")
        echo "Switching to 5.1 espressif repo"
        change_link "/home/pilnyt/arduino_idf51"
        ;;
    "Cancel - keep \"$CURRENT_ARD\"")
        echo "Canceled"
        ;;
    *)
        echo "Invalid option \"$REPLY\""
        ;;
esac