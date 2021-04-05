#rm underscoredpackages.txt
pushd source > /dev/null
  for folder in */
  do
    pushd $folder  > /dev/null
      for packageName in */
      do
        pushd $packageName > /dev/null
          if cat control/control | grep Package | grep _; then
            #echo $folder$packageName | tee -a ../../../underscoredpackages.txt
            #cat control/control | grep Package*_* | grep _ >> ../../../underscoredpackages.txt
            echo "building $folder$packageName"
            ../../../opkg-build -o 0 -g 0 .
            mv *.ipk ../../../$folder
          fi
        popd > /dev/null
      done
    popd > /dev/null
    pushd ../$folder > /dev/null
      echo "building $folder indices"
      ../../opkg-utils/opkg-make-index -p Packages -v .
    popd > /dev/null
  done
popd > /dev/null

