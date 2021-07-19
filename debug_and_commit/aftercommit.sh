for f in *_backup;
do
  new="$(echo $f | sed 's/_backup//')"
  mv $f $new
done