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

unset CC CXX

# CORRECTED from an earlier draft of this script: libmpv has no Metal
# render-API backend (see include/mpv/render.h — only OpenGL and SW exist).
# mpv's own upstream iOS support (video/out/hwdec/hwdec_ios_gl.m, gated by
# meson's `ios-gl` feature) targets OpenGL ES via EAGL, with VideoToolbox
# hardware frames imported through CVOpenGLESTextureCache. That is the path
# this build enables:
#   -Dgl=enabled:      builds the OpenGL/GLES backend (required for libmpv's
#                       render API to expose MPV_RENDER_API_TYPE_OPENGL)
#   -Dios-gl=enabled:   builds the CVOpenGLESTextureCache-based VideoToolbox
#                       hwdec interop for GLES specifically
#   -Dvulkan=disabled:  no MoltenVK path on iOS in this build (that path
#                       depends on AppKit/NSApplication and doesn't apply)
# --Dlibmpv=true: build the C API library our Swift wrapper links against.
# --Dcplayer=false: we don't need the mpv CLI player binary, only libmpv.
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	--default-library=static \
	-Diconv=disabled -Dlua=enabled \
	-Dlibmpv=true -Dcplayer=false \
	-Dmanpage-build=disabled \
	-Dgl=enabled -Dios-gl=enabled \
	-Dvulkan=disabled -Dvdpau=disabled -Dvaapi=disabled -Ddrm=disabled \
	-Dx11=disabled -Dwayland=disabled \
	-Dcocoa=disabled

ninja -C $build -j$cores

# mpv-android's own mpv.sh carries an equivalent check in the opposite
# direction (it requests --default-library shared and forces a clean
# rebuild if meson produced a static .a instead, due to a known meson
# caching quirk where a stale build dir can retain the previous
# --default-library choice after it's changed). We request static here, so
# the failure mode we guard against is the mirror image: a stale build dir
# still holding a shared .dylib from an earlier run/config.
if [ -f "$build/libmpv.dylib" ] || ls "$build"/libmpv.*.dylib >/dev/null 2>&1; then
	echo >&2 "meson produced a shared library despite --default-library=static (stale build dir?), forcing clean rebuild."
	$0 clean
	exec $0 build
fi

DESTDIR="$prefix_dir" ninja -C $build install
