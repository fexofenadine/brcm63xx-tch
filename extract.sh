mkdir source
for sourceFolder in base luci management packages/packages routing telephony
do
#sourceFolder="${1%}"
  if [ "$sourceFolder" == "packages/packages" ]
  then
    mkdir source/packages
    mkdir source/packages/packages
  else
    mkdir source/$sourceFolder
  fi
  for fileName in $sourceFolder/*.ipk
  do
    echo "Processing $fileName file.."

    folderName="${fileName%.*}"  #remove trailing extension from folder
    echo $destName
    mkdir source/$folderName
    tar -xf $fileName --strip-components=0 -C source/$folderName
    mkdir source/$folderName/control
    tar -xf source/$folderName/control.tar.gz -C source/$folderName/control
    mkdir source/$folderName/data
    tar -xf source/$folderName/data.tar.gz -C source/$folderName/data
    rm source/$folderName/*.tar.gz
  done
  if [ "$sourceFolder" == "packages/packages" ]  
  then
    mv source/packages/packages/* source/packages  #remove nesting in packages repo
    rm -rf source/packages/packages
  fi
done
