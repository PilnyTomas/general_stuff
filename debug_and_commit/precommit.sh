for f in *.c;
do
  cp $f "${f}_backup";
  sed '/DEBUGLN/d' "${f}_backup" | sed '/DEBUGF/d'   | sed '/\/\/ debug/d' > "${f}";
done

for f in *.cpp;
do
  cp $f "${f}_backup";
  sed '/DEBUGLN/d' "${f}_backup" | sed '/DEBUGF/d'   | sed '/\/\/ debug/d' > "${f}";
done

for f in *.h;
do
  cp $f "${f}_backup";
  sed '/#include "DEBUG.h"/d' "${f}_backup" > "${f}";
done
