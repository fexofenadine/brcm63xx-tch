git config core.ignorecase false
pushd source > /dev/null
  for folder in */
  do
    pushd $folder  > /dev/null
      for packageName in */
      do
        pushd $packageName > /dev/null
          echo "rebasing "$folder$packageName
          #git mv CONTROL temp
          #git mv temp CONTROL
          mv CONTROL temp
          mv temp CONTROL
          #mv data/* .
          #rm -rf data
        popd > /dev/null
      done
    popd > /dev/null
  done
popd > /dev/null
git add -u ./source
#git add ./source
git commit -m "fixed CONTROL folder case"
git push
