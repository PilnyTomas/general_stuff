#!/bin/bash

idf.py &> /dev/null
if [ $? -ne 0 ]
then
  . ~/ex
fi

BACKTRACE=""
ELF_FILE=$(find "$HOME/Arduino_builds/" -name "*.elf")
SUBL=false

while getopts ":b:e:s" opt; do
  case "${opt}" in
    b)
      BACKTRACE="${OPTARG}"
      ;;
    e)
      ELF_FILE="${OPTARG}"
      ;;
    s)
      echo "DEBUG: got SUBL"
      SUBL=true
      ;;
    *)
      echo "Usage: $0 [--elf <ELF_FILE.elf>] [--subl]"
      echo "    --elf <ELF_FILE.elf>    Specify path to .elf ELF_FILE. If not used by default using ~/Arduino_builds/*.elf"
      echo "    --subl    opens backtrace ELF_FILEs in sublime text"
      #exit 0
      ;;
  esac
done
shift $((OPTIND-1))

echo " * Using ELF_FILE \"$ELF_FILE\""
echo " * Using BACKTRACE \"$BACKTRACE\""

if [ -z "$BACKTRACE" -o -z "$ELF_FILE" ]; then
  echo "Invalid input! Terminating."
  exit
fi

xtensa-esp32-elf-addr2line -piaf -e $ELF_FILE $BACKTRACE

#if [ "$2" == "--subl" ] #old
if [ $SUBL == true ]
then
  subl $(xtensa-esp32-elf-addr2line -piaf -e $ELF_FILE $BACKTRACE | grep -o "/.*" | sed 's/\s(discriminator.*//')
fi
