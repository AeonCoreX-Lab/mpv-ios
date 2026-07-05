#!/bin/bash -e

. ../../include/path.sh

build=_build$ndk_suffix

if [ "$1" == "build" ]; then
	true
elif [ "$1" == "clean" ]; then
	rm -rf $build
	exit 0
else
	exit 255
fi

unset CC CXX # meson wants these unset

# Flags below are deliberately minimal, matching mpv-android's own
# libxml2 build exactly (buildscripts/scripts/libxml2.sh in mpv-android).
# Two earlier versions of this script tried to be more explicit by also
# passing -Dhttp=disabled, -Dlzma=disabled, -Dftp=disabled, and
# -Dzlib=disabled — this caused two consecutive CI failures ("Unknown
# option: ftp", then "Unknown option: lzma") because libxml2 2.14/2.15
# removed those meson options from the codebase entirely (see libxml2's
# NEWS file: HTTP, LZMA, and FTP support were all removed around that
# time), not merely defaulted them off. mpv-android's own script never had
# this problem because it only ever set the options it actually needs
# (push/reader/sax1/iso8859x/pattern enabled, minimum build otherwise),
# leaving every optional feature at upstream's own default — which is the
# more version-resilient approach and the one this script now follows.
#
# If you need to verify the current option list for some future change,
# check https://github.com/GNOME/libxml2/blob/master/meson_options.txt
# rather than guessing from an older version's docs or another project's
# build script — removing flags one CI failure at a time (as happened
# here) burns a full pipeline run per guess.
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	-Dminimum=true -D{push,reader,sax1,iso8859x,pattern}=enabled

ninja -C $build -j$cores
DESTDIR="$prefix_dir" ninja -C $build install
