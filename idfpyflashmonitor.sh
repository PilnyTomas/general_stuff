idf.py 2> /dev/null
ret=$?
if [ $ret -ne 0 ]; then
  . ~/ex
fi

#ll /dev/ttyUSB*  # todo make it automatically choose

if [ -z "$1" ]; then
  echo "# # # No port specifiaction given, calling static \"idf.py -p /dev/ttyUSB0 monitor flash\""
  idf.py -p /dev/ttyUSB0 monitor flash
else
  echo "# # # specified port number \"$1\" , calling \"idf.py -p /dev/ttyUSB$1 monitor flash\""

  idf.py -p /dev/ttyUSB$1 monitor flash
fi
