count=`ls -1 *.c 2>/dev/null | wc -l`
if [ $count != 0 ]
then
  for f in *.c;
  do
    if test -f "${f}_backup"; then
      echo "${f}_backup already exists - no action taken."
    else
      if [[ -L "${f}" ]]
      then
        echo "${f} is a symlink - no action taken."
      else
        cp $f "${f}_backup";
        sed '/DEBUGLN/d' "${f}_backup" | sed '/DEBUGF/d'   | sed '/\/\/ debug/d' > "${f}";
      fi
    fi
  done
fi

count=`ls -1 *.cpp 2>/dev/null | wc -l`
if [ $count != 0 ]
then
  for f in *.cpp;
  do
    if test -f "${f}_backup"; then
      echo "${f}_backup already exists - no action taken."
    else
      if [[ -L "${f}" ]]
      then
        echo "${f} is a symlink - no action taken."
      else
        cp $f "${f}_backup";
        sed '/DEBUGLN/d' "${f}_backup" | sed '/DEBUGF/d'   | sed '/\/\/ debug/d' > "${f}";
      fi
    fi
  done
fi

count=`ls -1 *.h 2>/dev/null | wc -l`
if [ $count != 0 ]
then
  for f in *.h;
  do
    if test -f "${f}_backup"; then
      echo "${f}_backup already exists - no action taken."
    else
      if [[ -L "${f}" ]]
      then
        echo "${f} is a symlink - no action taken."
      else
        cp $f "${f}_backup";
        sed '/#include "DEBUG.h"/d' "${f}_backup" > "${f}";
      fi
    fi
  done
fi