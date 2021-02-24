#!/bin/bash

echo
echo "### DOWNLOAD IOS SOURCE ###"
echo

# find the latest ID here : https://api.github.com/repos/NordicSemiconductor/IOS-Pods-DFU-Library/releases/latest
github_repo_owner=NordicSemiconductor
github_repo=IOS-Pods-DFU-Library
github_release_id=32090814
github_info_file="$github_repo_owner.$github_repo.$github_release_id.info.json"

if [ ! -f "$github_info_file" ]; then
    echo
    echo "### DOWNLOAD GITHUB INFORMATION ###"
    echo
    github_info_file_url=https://api.github.com/repos/$github_repo_owner/$github_repo/releases/$github_release_id
    echo "Downloading $github_info_file_url to $github_info_file"
    curl -s $github_info_file_url > $github_info_file
fi

# Set version
github_tag_name=`cat $github_info_file | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//'`
github_short_version=`echo "$github_tag_name" | sed 's/.LTS//'`

# Static configuration
zip_folder="iOS/Zips"
zip_file_name="$github_short_version.zip"
zip_file="$zip_folder/$zip_file_name"
zip_url="http://github.com/$github_repo_owner/$github_repo/zipball/$github_tag_name"

if [ ! -f "$zip_file" ]; then
    echo
    echo "### DOWNLOAD GITHUB RELEASE FILES ###"
    echo

    mkdir -p $zip_folder
    curl -L -o $zip_file $zip_url

    if [ ! -f "$zip_file" ]; then
        echo "Failed to download $zip_url into $zip_file"
        exit 1
    fi

    echo "Downloaded $zip_url into $zip_file"
fi

echo
echo "### UNZIP SOURCE ###"
echo

source_folder="iOS/Source"
rm -rf $source_folder
unzip -qq -n -d "$source_folder" "$zip_file"
if [ ! -d "$source_folder" ]; then
    echo "Failed"
    exit 1
fi
echo "Unzipped $zip_file into $source_folder"

echo
echo "### XBUILD ###"
echo

xbuild=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild

xbuild_parameters=""
xbuild_parameters="${xbuild_parameters} ONLY_ACTIVE_ARCH=NO"
xbuild_parameters="${xbuild_parameters} ENABLE_BITCODE=NO"
xbuild_parameters="${xbuild_parameters} ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES"

if [ ! "$verbose" = "1" ]; then
    xbuild_parameters="${xbuild_parameters} -quiet"
fi
xbuild_parameters="${xbuild_parameters} -project $source_folder/**/_Pods.xcodeproj"
xbuild_parameters="${xbuild_parameters} -configuration Release"

echo "xbuild_parameters = $xbuild_parameters -sdk iphoneos build"
echo

$xbuild $xbuild_parameters -sdk iphoneos build
$xbuild $xbuild_parameters -sdk iphonesimulator build

iOSDFULibrary_iphoneos_framework=`find ./$source_folder/ -ipath "*iphoneos*" -iname "iOSDFULibrary.framework" | head -n 1`
ZIPFoundation_iphoneos_framework=`find ./$source_folder/ -ipath "*iphoneos*" -iname "ZIPFoundation.framework" | head -n 1`
iOSDFULibrary_iphonesimulator_framework=`find ./$source_folder/ -ipath "*iphonesimulator*" -iname "iOSDFULibrary.framework" | head -n 1`
ZIPFoundation_iphonesimulator_framework=`find ./$source_folder/ -ipath "*iphonesimulator*" -iname "ZIPFoundation.framework" | head -n 1`

if [ ! -d "$iOSDFULibrary_iphoneos_framework" ]; then
    echo "Failed : $iOSDFULibrary_iphoneos_framework does not exist"
    exit 1
fi
if [ ! -d "$ZIPFoundation_iphoneos_framework" ]; then
    echo "Failed : $ZIPFoundation_iphoneos_framework does not exist"
    exit 1
fi
if [ ! -d "$iOSDFULibrary_iphonesimulator_framework" ]; then
    echo "Failed : $iOSDFULibrary_iphonesimulator_framework does not exist"
    exit 1
fi
if [ ! -d "$ZIPFoundation_iphonesimulator_framework" ]; then
    echo "Failed : $ZIPFoundation_iphonesimulator_framework does not exist"
    exit 1
fi

echo "Created :"
echo "  - $iOSDFULibrary_iphoneos_framework"
echo "  - $ZIPFoundation_iphoneos_framework"
echo "  - $iOSDFULibrary_iphonesimulator_framework"
echo "  - $ZIPFoundation_iphonesimulator_framework"

echo
echo "### LIPO / CREATE FAT LIBRARY ###"
echo

frameworks_folder="iOS/Frameworks"

rm -rf $frameworks_folder
cp -a $(dirname $iOSDFULibrary_iphoneos_framework)/. $frameworks_folder
cp -a $(dirname $ZIPFoundation_iphoneos_framework)/. $frameworks_folder

rm -rf $frameworks_folder/iOSDFULibrary.framework/iOSDFULibrary
lipo -create -output $frameworks_folder/iOSDFULibrary.framework/iOSDFULibrary $iOSDFULibrary_iphoneos_framework/iOSDFULibrary $iOSDFULibrary_iphonesimulator_framework/iOSDFULibrary
lipo -info $frameworks_folder/iOSDFULibrary.framework/iOSDFULibrary

# TODO : Create Laerdal.Xamarin.ZipFoundation.iOS
#rm -rf $frameworks_folder/ZIPFoundation.framework/ZIPFoundation
#lipo -create -output $frameworks_folder/ZIPFoundation.framework/ZIPFoundation $ZIPFoundation_iphoneos_framework/ZIPFoundation $ZIPFoundation_iphonesimulator_framework/ZIPFoundation
lipo -info $frameworks_folder/ZIPFoundation.framework/ZIPFoundation

echo
echo "### SHARPIE ###"
echo

sharpie_folder="iOS/Sharpie"
sharpie_version=`sharpie -v`
sharpie_output_file=$sharpie_folder/ApiDefinitions.cs

sharpie bind -sdk iphoneos -o $sharpie_folder -f $frameworks_folder/iOSDFULibrary.framework