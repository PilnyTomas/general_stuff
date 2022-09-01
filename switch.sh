#!/bin/bash
# Bash Menu Script Example
ARDUINO='/home/pilnyt/Arduino/hardware/espressif/esp32'
IDF_COMPONENT='/home/pilnyt/esp/esp-idf/components/arduino'
CURRENT_ARD=$(ls -la ~/Arduino/hardware/espressif/ | grep '/home/pilnyt' | sed 's/^.*\///')
CURRENT_IDF=$(ls -la ~/esp/esp-idf/components/arduino | grep '/home/pilnyt' | sed 's/^.*\///')
echo "Current Arduino link: ${CURRENT_ARD}"
echo "Current IDF link: ${CURRENT_IDF}"
#echo "Switch Arduino-esp32 repo used for Arduino IDE from current \"$CURRENT\": "
options=("Main fork" "Secondary fork" "3rd fork - group by SoC" "4th fork - group by Manufacturer" "Main Espressif repo" "Cancel - keep \"$CURRENT_ARD\"")
select opt in "${options[@]}"
do
    case $opt in
        "Main fork")
            echo "Switching to main fork"
            rm $ARDUINO
            rm $IDF_COMPONENT
            ln -s /home/pilnyt/arduino-esp32-fork $ARDUINO
            ln -s /home/pilnyt/arduino-esp32-fork $IDF_COMPONENT
            break
            ;;
        "Secondary fork")
            echo "Switching to secondary fork"
            rm $ARDUINO
            rm $IDF_COMPONENT
            ln -s /home/pilnyt/arduino-esp32-fork2 $ARDUINO
            ln -s /home/pilnyt/arduino-esp32-fork2 $IDF_COMPONENT
            break
            ;;
        "3rd fork - group by SoC")
            echo "Switching to 3rd fork - group by SoC"
            rm $ARDUINO
            rm $IDF_COMPONENT
            ln -s /home/pilnyt/arduino-esp32-fork3 $ARDUINO
            ln -s /home/pilnyt/arduino-esp32-fork3 $IDF_COMPONENT
            break
            ;;
        "4th fork - group by Manufacturer")
            echo "Switching to 4th fork - group by Manufacturer"
            rm $ARDUINO
            rm $IDF_COMPONENT
            ln -s /home/pilnyt/arduino-esp32-fork4 $ARDUINO
            ln -s /home/pilnyt/arduino-esp32-fork4 $IDF_COMPONENT
            break
            break
            ;;
        "Main Espressif repo")
            echo "Switching to main espressif repo"
            rm $ARDUINO
            rm $IDF_COMPONENT
            ln -s /home/pilnyt/arduino-esp32 $ARDUINO
            ln -s /home/pilnyt/arduino-esp32 $IDF_COMPONENT
            break
            ;;
        "Cancel - keep \"$CURRENT_ARD\"")
            echo "Canceled"
            break
            ;;
        *)
            echo "Invalid option \"$REPLY\""
            break
            ;;
    esac
done
