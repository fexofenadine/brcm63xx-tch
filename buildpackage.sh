mkdir temp
cp * temp
pushd control
  tar --numeric-owner --group=0 --owner==0 -czf ../temp/control.tar.gz ./*
popd
pushd data
  tar --numeric-owner --group=0 --owner==0 -czf ../temp/data.tar.gz ./*
popd
pushd temp
  ar -rv ../test_package.ipk ./*
popd
rm -rf temp
