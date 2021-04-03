pushd source > /dev/null
  for folder in */
  do
    echo "making ../$folder"
    mkdir ../$folder
    pushd $folder > /dev/null
      for packageName in */
      do
        pushd $packageName > /dev/null
        echo "building $folder$packageName"
          ../../../../opkg-utils/opkg-build -o 0 -g 0 .
          mv *.ipk ../../../$folder
        popd > /dev/null
      done
    popd > /dev/null
    pushd ../$folder > /dev/null
      echo "building $folder indices"
      ../../opkg-utils/opkg-make-index -p Packages -v .
    popd > /dev/null
  done
popd > /dev/null
