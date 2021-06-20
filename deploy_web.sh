#!/bin/zsh -x
flutter build web --release
if [ $? != 0 ] ; then
    exit 1
fi
rm -rf $HOME/github/aisleriot/docs/run
mkdir $HOME/github/aisleriot/docs/run
cd $HOME/github/aisleriot
cp -r build/web/* $HOME/github/aisleriot/docs/run/

