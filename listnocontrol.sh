rm nocontrol.txt
pushd source > /dev/null
  for folder in */
  do
    pushd $folder  > /dev/null
      for packageName in */
      do
        pushd $packageName > /dev/null
          if [ ! -f "control/control" ]; then
            echo $folder$packageName" control file not found" | tee -a ../../../nocontrol.txt
          fi
        popd > /dev/null
      done
    popd > /dev/null
  done
popd > /dev/null
