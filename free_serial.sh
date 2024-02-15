echo "Checking \"/dev/ttyUSB$1\""
kill $(sudo lsof /dev/ttyUSB$1 2> /dev/null | grep "/dev/ttyUSB$1" | sed 's/^ *[^ ]* *\([^ ]*\) .*/\1/')
#sudo lsof /dev/ttyUSB$1 2> /dev/null | grep "/dev/ttyUSB$1" | sed 's/^ *[^ ]* *\([^ ]*\) .*/\1/'