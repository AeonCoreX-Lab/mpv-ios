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

# Only vulkan needs to be explicitly disabled here — it's unavailable on
# iOS and meson's dependency auto-detection can't be trusted to skip it
# reliably in a cross-compile sysroot. d3d11/opengl/glslang/shaderc are all
# `type: 'feature', value: 'auto'` options in libplacebo's own
# meson_options.txt: with none of their dependencies present in our
# cross-compiled prefix, auto-detection already resolves them to off
# without needing to name them explicitly. Matching mpv-android's own
# libplacebo.sh here deliberately (it only passes -Dvulkan=disabled
# -Ddemos=false) rather than listing every related flag defensively, since
# passing extra explicit flags is exactly what broke the libxml2 build
# after an upstream option was removed — every flag pinned here is one
# more thing that can go stale on a future libplacebo update.
#
# mpv itself renders on iOS via OpenGL ES/EAGL, not libplacebo's own
# opengl or vulkan backends directly (see MPVGLView.swift and the main
# README's "Architecture notes" section) — libplacebo is used here purely
# as mpv's internal shader/rendering-primitives helper library.
meson setup $build --cross-file "$prefix_dir"/crossfile.txt \
	-Dvulkan=disabled -Ddemos=false

ninja -C $build -j$cores
DESTDIR="$prefix_dir" ninja -C $build install

# add missing library for static linking (same meson bug noted upstream:
# https://github.com/mesonbuild/meson/issues/11300)
${SED:-sed} '/^Libs:/ s|$| -lc++|' "$prefix_dir/lib/pkgconfig/libplacebo.pc" -i
