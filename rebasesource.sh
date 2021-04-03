rm underscoredpackages.txt
pushd source > /dev/null
  for folder in */
  do
    pushd $folder  > /dev/null
      for packageName in */
      do
        pushd $packageName > /dev/null
          echo "rebasing "$folder$packageName
          mv control temp
          mv temp CONTROL
          mv data/* .
          rm -rf data
        popd > /dev/null
      done
    popd > /dev/null
  done
popd > /dev/null
