#!/bin/sh
echo "Cleaning builds"
xcodebuild -configuration Debug -sdk iphoneos3.1 clean
xcodebuild -configuration Release -sdk iphoneos3.1 clean
xcodebuild -configuration Debug -sdk iphoneos3.1
xcodebuild -configuration Release -sdk iphoneos3.1
xcodebuild -configuration Debug -sdk iphonesimulator3.1 clean
xcodebuild -configuration Release -sdk iphonesimulator3.1 clean
xcodebuild -configuration Debug -sdk iphonesimulator3.1
xcodebuild -configuration Release -sdk iphonesimulator3.1
rm -fr build/package
mkdir -p build/package/include
mkdir -p build/package/lib
cp build/**/lib*.a build/package/lib
cp *.h build/package/include
cd build/package
zip -r libEasyURLDownloader.zip *
cp libEasyURLDownloader.zip ..
cd ..
