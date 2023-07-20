#!/bin/bash
# Bash Menu Script Example
ARDUINO='/home/pilnyt/Arduino/hardware/espressif/esp32'
#ARDUINO2='/home/.arduino15/packages/esp32/hardware/esp32/'
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

case $opt in
    "Main fork")
        echo "Switching to main fork"
        rm $ARDUINO
        rm $IDF_COMPONENT
        ln -s /home/pilnyt/arduino-esp32-fork $ARDUINO
        ln -s /home/pilnyt/arduino-esp32-fork $IDF_COMPONENT
        ;;
    "Secondary fork")
        echo "Switching to secondary fork"
        rm $ARDUINO
        rm $IDF_COMPONENT
        ln -s /home/pilnyt/arduino-esp32-fork2 $ARDUINO
        ln -s /home/pilnyt/arduino-esp32-fork2 $IDF_COMPONENT
        ;;
    "3rd fork")
        echo "Switching to 3rd fork"
        rm $ARDUINO
        rm $IDF_COMPONENT
        ln -s /home/pilnyt/arduino-esp32-fork3 $ARDUINO
        ln -s /home/pilnyt/arduino-esp32-fork3 $IDF_COMPONENT
        ;;
    "4th fork")
        echo "Switching to 4th fork"
        rm $ARDUINO
        rm $IDF_COMPONENT
        ln -s /home/pilnyt/arduino-esp32-fork4 $ARDUINO
        ln -s /home/pilnyt/arduino-esp32-fork4 $IDF_COMPONENT
        ;;
    "5th fork")
        echo "Switching to 5th fork"
        rm $ARDUINO
        rm $IDF_COMPONENT
        ln -s /home/pilnyt/arduino-esp32-fork5 $ARDUINO
        ln -s /home/pilnyt/arduino-esp32-fork5 $IDF_COMPONENT
        ;;
    "Espressif repo for PRs")
        echo "Switching to main espressif repo for PRs"
        rm $ARDUINO
        rm $IDF_COMPONENT
        ln -s /home/pilnyt/arduino-esp32-pr $ARDUINO
        ln -s /home/pilnyt/arduino-esp32-pr $IDF_COMPONENT
        ;;
    "Main Espressif repo")
        echo "Switching to main espressif repo"
        rm $ARDUINO
        rm $IDF_COMPONENT
        ln -s /home/pilnyt/arduino-esp32 $ARDUINO
        ln -s /home/pilnyt/arduino-esp32 $IDF_COMPONENT
        ;;
    "5.1 Espressif repo")
        echo "Switching to 5.1 espressif repo"
        rm $ARDUINO
        rm $IDF_COMPONENT
        ln -s /home/pilnyt/arduino_idf51 $ARDUINO
        ln -s /home/pilnyt/arduino_idf51 $IDF_COMPONENT
        ;;
    "Cancel - keep \"$CURRENT_ARD\"")
        echo "Canceled"
        ;;
    *)
        echo "Invalid option \"$REPLY\""
        ;;
esac