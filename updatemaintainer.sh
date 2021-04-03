pushd source > /dev/null
  for folder in */
  do
    pushd $folder  > /dev/null
      for packageName in */
      do
        pushd $packageName > /dev/null
          echo "updating maintainer in $folder$packageName"
          sed -i 's/Maintainer/Old_Maintainer/g' control/control
          sed -i '/^Section.*/a Maintainer: fexofenadine (github.com/fexofenadine)' control/control
        popd > /dev/null
      done
    popd > /dev/null
  done
popd > /dev/null
