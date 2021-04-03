pushd source > /dev/null
  for folder in */
  do
    pushd $folder  > /dev/null
      for packageName in */
      do
        pushd $packageName > /dev/null
          echo "concatenating description of "$folder$packageName
          sed -i -e :a -e '$!N;s/\n / /;ta' -e 'P;D' control/control #concatenate Description field with any following lines beginning with " "
          sed -i 's/  / /g' control/control #replace "  " with " "
        popd > /dev/null
      done
    popd > /dev/null
  done
popd > /dev/null
