#!/usr/bin/env bash
#
# Build the static iOS dependencies used by Makefile.iPhone.Theos.
#
# Usage:
#   scripts/build-ios-deps.sh [output-directory]
#
# Environment:
#   THEOS        Theos root (defaults to $THEOS or ~/theos)
#   SDKVERSION   iPhoneOS SDK version (default: 6.1)
#   ARCH         target architecture (default: armv7)
#   DEPLOYMENT   minimum iOS version (default: 6.0)
#   FORCE        set to 1 to rebuild everything
#
# The script downloads the official ONScripter iOS SDK sources (SDL 1.3 with
# the iOS 6 UIKit backend, SDL_image, SDL_mixer, SDL_ttf, FreeType, libogg,
# Tremor and libmad) plus libjpeg, then cross-compiles them with the Theos
# toolchain.  Everything is installed into <output>/include and <output>/lib.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/deps}"
SDKVERSION="${SDKVERSION:-6.1}"
ARCH="${ARCH:-armv7}"
DEPLOYMENT="${DEPLOYMENT:-6.0}"

THEOS="${THEOS:-$HOME/theos}"
SDK="$THEOS/sdks/iPhoneOS${SDKVERSION}.sdk"

if [[ ! -d "$SDK" ]]; then
    echo "error: iOS SDK not found at $SDK" >&2
    exit 1
fi

if [[ -x "$THEOS/toolchain/linux/iphone/bin/clang" ]]; then
    CC="$THEOS/toolchain/linux/iphone/bin/clang"
    AR="$THEOS/toolchain/linux/iphone/bin/llvm-ar"
    RANLIB="$THEOS/toolchain/linux/iphone/bin/ranlib"
    AR_DARWIN=1
elif command -v xcrun >/dev/null 2>&1; then
    CC="$(xcrun --find clang)"
    AR="$(xcrun --find ar)"
    RANLIB="$(xcrun --find ranlib)"
    AR_DARWIN=0
else
    CC="${CC:-clang}"
    AR="${AR:-ar}"
    RANLIB="${RANLIB:-ranlib}"
    AR_DARWIN=0
fi

SRC="$OUT/src"
DL="$OUT/downloads"
INC="$OUT/include"
LIB="$OUT/lib"
mkdir -p "$SRC" "$DL" "$INC" "$LIB"

TARGET_FLAGS="-target ${ARCH}-apple-ios${DEPLOYMENT} -isysroot $SDK"
CFLAGS="$TARGET_FLAGS -O2 -Wno-everything"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

make_archive() {
    local dir="$1"
    local name="$2"
    shift 2

    ( cd "$dir"
      rm -f "lib${name}.a"
      local files
      if [[ $# -gt 0 ]]; then
          files=("$@")
      else
          files=(*.o)
      fi
      if [[ "$AR_DARWIN" == 1 ]]; then
          "$AR" --format=darwin rcs "lib${name}.a" "${files[@]}"
      else
          "$AR" rcs "lib${name}.a" "${files[@]}"
      fi
      "$RANLIB" "lib${name}.a" )
}

fetch() {
    local url="$1"
    local file="$2"

    if [[ ! -f "$DL/$file" ]]; then
        if ! command -v curl >/dev/null 2>&1; then
            echo "error: curl is required to download $file" >&2
            exit 1
        fi
        echo "==> Downloading $file"
        curl -L --fail --retry 3 -o "$DL/$file" "$url"
    fi
}

download_sources() {
    if [[ ! -d "$SRC/onscripter_ios" ]]; then
        fetch "https://github.com/ogapee/onscripter_ios/archive/refs/tags/20240910.tar.gz" \
            "onscripter_ios-20240910.tar.gz"
        tar -xzf "$DL/onscripter_ios-20240910.tar.gz" -C "$SRC"
        mv "$SRC/onscripter_ios-20240910" "$SRC/onscripter_ios"
    fi

    if [[ ! -d "$SRC/jpeg-9e" ]]; then
        fetch "https://www.ijg.org/files/jpegsrc.v9e.tar.gz" "jpegsrc.v9e.tar.gz"
        tar -xzf "$DL/jpegsrc.v9e.tar.gz" -C "$SRC"
    fi
}

build_ogg() {
    [[ -f "$LIB/libogg.a" && "${FORCE:-0}" != 1 ]] && return

    echo "==> Building libogg"
    local dir="$SRC/onscripter_ios/libogg-1.3.1"
    ( cd "$dir"
      make distclean >/dev/null 2>&1 || true
      CC="$CC" CFLAGS="$CFLAGS" ./configure \
          --host=arm-apple-darwin --disable-shared --enable-static \
          --prefix="$OUT" >/dev/null
      make -j"$JOBS" -C src libogg.la >/dev/null )
    cp "$dir/src/.libs/libogg.a" "$LIB/"
    rm -rf "$INC/ogg"
    mkdir -p "$INC/ogg"
    cp "$dir"/include/ogg/*.h "$INC/ogg/"
}

build_tremor() {
    [[ -f "$LIB/libvorbisidec.a" && "${FORCE:-0}" != 1 ]] && return

    echo "==> Building Tremor (libvorbisidec)"
    if ! command -v autoreconf >/dev/null 2>&1; then
        echo "error: autoreconf is required to build Tremor" >&2
        exit 1
    fi
    local dir="$SRC/onscripter_ios/libvorbisidec-1.0.2+svn18153"
    ( cd "$dir"
      make distclean >/dev/null 2>&1 || true
      autoreconf -fi >/dev/null 2>&1
      CC="$CC" CFLAGS="$CFLAGS" \
          OGG_CFLAGS="-I$INC" OGG_LIBS="-L$LIB" \
          ./configure --host=arm-apple-darwin --disable-shared --enable-static \
          --prefix="$OUT" >/dev/null
      make -j"$JOBS" libvorbisidec.la >/dev/null )
    cp "$dir/.libs/libvorbisidec.a" "$LIB/"
    rm -rf "$INC/tremor"
    mkdir -p "$INC/tremor"
    cp "$dir/ivorbiscodec.h" "$dir/ivorbisfile.h" "$dir/config_types.h" "$INC/tremor/"
}

build_mad() {
    [[ -f "$LIB/libmad.a" && "${FORCE:-0}" != 1 ]] && return

    echo "==> Building libmad"
    local dir="$SRC/onscripter_ios/libmad-0.15.1b"
    ( cd "$dir"
      make distclean >/dev/null 2>&1 || true
      CC="$CC" CFLAGS="$CFLAGS" ./configure \
          --host=arm-apple-darwin --disable-shared --enable-static \
          --disable-aso --prefix="$OUT" >/dev/null
      # libmad's configure adds GCC-only optimisation flags.
      sed -i.bak -E \
          's/-f(force-mem|force-addr|thread-jumps|cse-follow-jumps|cse-skip-blocks|expensive-optimizations|regmove|schedule-insns2|strength-reduce) //g' \
          Makefile
      make -j"$JOBS" libmad.la >/dev/null )
    cp "$dir/.libs/libmad.a" "$LIB/"
    cp "$dir/mad.h" "$INC/"
}

build_freetype() {
    [[ -f "$LIB/libfreetype.a" && "${FORCE:-0}" != 1 ]] && return

    echo "==> Building FreeType"
    local dir="$SRC/onscripter_ios/freetype-2.4.8"
    ( cd "$dir"
      make distclean >/dev/null 2>&1 || true
      CC="$CC" CFLAGS="$CFLAGS" ./configure \
          --host=arm-apple-darwin --disable-shared --enable-static \
          --without-zlib --without-bzip2 --prefix="$OUT" >/dev/null
      make -j"$JOBS" >/dev/null )
    cp "$dir/objs/.libs/libfreetype.a" "$LIB/"
    rm -rf "$INC/freetype"
    cp -R "$dir/include/freetype" "$INC/"
    cp "$dir/include/ft2build.h" "$INC/"
}

build_jpeg() {
    [[ -f "$LIB/libjpeg.a" && "${FORCE:-0}" != 1 ]] && return

    echo "==> Building libjpeg"
    local dir="$SRC/jpeg-9e"
    ( cd "$dir"
      make distclean >/dev/null 2>&1 || true
      CC="$CC" CFLAGS="$CFLAGS" ./configure \
          --host=arm-apple-darwin --disable-shared --enable-static \
          --prefix="$OUT" >/dev/null
      make -j"$JOBS" libjpeg.la >/dev/null )
    cp "$dir/.libs/libjpeg.a" "$LIB/"
    cp "$dir/jpeglib.h" "$dir/jconfig.h" "$dir/jmorecfg.h" "$INC/"
}

build_sdl() {
    [[ -f "$LIB/libSDL.a" && "${FORCE:-0}" != 1 ]] && return

    echo "==> Building SDL 1.3 (iOS)"
    local dir="$SRC/onscripter_ios/SDL"
    local obj="$OUT/obj/SDL"
    mkdir -p "$obj"

    local files=(
        src/timer/unix/SDL_systimer.c
        src/timer/SDL_timer.c
        src/stdlib/SDL_string.c
        src/audio/dummy/SDL_dummyaudio.c
        src/audio/SDL_audio.c
        src/audio/SDL_audiocvt.c
        src/audio/SDL_audiotypecvt.c
        src/audio/SDL_mixer.c
        src/audio/SDL_wave.c
        src/cpuinfo/SDL_cpuinfo.c
        src/events/SDL_events.c
        src/events/SDL_keyboard.c
        src/events/SDL_mouse.c
        src/events/SDL_quit.c
        src/events/SDL_windowevents.c
        src/file/SDL_rwops.c
        src/SDL_compat.c
        src/SDL_error.c
        src/SDL_fatal.c
        src/SDL.c
        src/thread/pthread/SDL_syscond.c
        src/thread/pthread/SDL_sysmutex.c
        src/thread/pthread/SDL_syssem.c
        src/thread/pthread/SDL_systhread.c
        src/thread/SDL_thread.c
        src/stdlib/SDL_getenv.c
        src/stdlib/SDL_iconv.c
        src/stdlib/SDL_malloc.c
        src/stdlib/SDL_qsort.c
        src/stdlib/SDL_stdlib.c
        src/video/SDL_blit.c
        src/video/SDL_blit_0.c
        src/video/SDL_blit_1.c
        src/video/SDL_blit_A.c
        src/video/SDL_blit_auto.c
        src/video/SDL_blit_copy.c
        src/video/SDL_blit_N.c
        src/video/SDL_blit_slow.c
        src/video/SDL_bmp.c
        src/video/SDL_pixels.c
        src/video/SDL_rect.c
        src/video/SDL_RLEaccel.c
        src/video/SDL_stretch.c
        src/video/SDL_surface.c
        src/video/SDL_video.c
        src/video/dummy/SDL_nullevents.c
        src/video/dummy/SDL_nullvideo.c
        src/joystick/SDL_joystick.c
        src/joystick/iphoneos/SDL_sysjoystick.m
        src/joystick/iphoneos/SDLUIAccelerationDelegate.m
        src/video/uikit/SDL_uikitevents.m
        src/video/uikit/SDL_uikitopengles.m
        src/video/uikit/SDL_uikitvideo.m
        src/video/uikit/SDL_uikitview.m
        src/video/uikit/SDL_uikitwindow.m
        src/video/uikit/SDL_uikitopenglview.m
        src/video/uikit/SDL_uikitappdelegate.m
        src/loadso/dlopen/SDL_sysloadso.c
        src/video/uikit/jumphack.c
        src/haptic/dummy/SDL_syshaptic.c
        src/haptic/SDL_haptic.c
        src/video/SDL_fillrect.c
        src/SDL_assert.c
        src/power/SDL_power.c
        src/power/uikit/SDL_syspower.m
        src/file/cocoa/SDL_rwopsbundlesupport.m
        src/video/SDL_clipboard.c
        src/events/SDL_clipboardevents.c
        src/events/SDL_gesture.c
        src/events/SDL_touch.c
        src/atomic/SDL_atomic.c
        src/atomic/SDL_spinlock.c
        src/render/SDL_render.c
        src/render/SDL_yuv_mmx.c
        src/render/SDL_yuv_sw.c
        src/render/software/SDL_blendfillrect.c
        src/render/software/SDL_blendline.c
        src/render/software/SDL_blendpoint.c
        src/render/software/SDL_drawline.c
        src/render/software/SDL_drawpoint.c
        src/video/dummy/SDL_nullframebuffer.c
        src/render/software/SDL_render_sw.c
        src/render/opengles/SDL_render_gles.c
        src/SDL_hints.c
        src/render/opengles2/SDL_render_gles2.c
        src/render/opengles2/SDL_shaders_gles2.c
        src/SDL_log.c
        src/audio/coreaudio/SDL_coreaudio.c
        src/video/uikit/SDL_uikitviewcontroller.m
        src/video/uikit/SDL_uikitmodes.m
    )

    ( cd "$dir"
      for f in "${files[@]}"; do
          "$CC" $CFLAGS -I"$dir/include" -I"$dir/src" -c "$f" \
              -o "$obj/$(basename "$f").o"
      done
      make_archive "$obj" SDL )

    cp "$obj/libSDL.a" "$LIB/"
    rm -rf "$INC/SDL"
    mkdir -p "$INC/SDL"
    cp "$dir"/include/*.h "$INC/SDL/"
}

build_sdl_image() {
    [[ -f "$LIB/libSDL_image.a" && "${FORCE:-0}" != 1 ]] && return

    echo "==> Building SDL_image"
    local dir="$SRC/onscripter_ios/SDL_image"
    local obj="$OUT/obj/SDL_image"
    mkdir -p "$obj"

    ( cd "$dir"
      for f in IMG.c IMG_bmp.c IMG_gif.c IMG_jpg.c IMG_lbm.c IMG_pcx.c \
               IMG_png.c IMG_pnm.c IMG_tga.c IMG_tif.c IMG_webp.c IMG_xcf.c \
               IMG_xpm.c IMG_xv.c IMG_xxx.c IMG_ImageIO.m; do
          "$CC" $CFLAGS -I. -I"$dir/../SDL/include" \
              -DLOAD_BMP -DLOAD_GIF -DLOAD_JPG -DLOAD_LBM -DLOAD_PCX \
              -DLOAD_PNG -DLOAD_PNM -DLOAD_TGA -DLOAD_TIF -DLOAD_XPM -DLOAD_XV \
              -c "$f" -o "$obj/${f%.*}.o"
      done
      make_archive "$obj" SDL_image )

    cp "$obj/libSDL_image.a" "$LIB/"
    cp "$dir/SDL_image.h" "$INC/"
}

build_sdl_mixer() {
    [[ -f "$LIB/libSDL_mixer.a" && "${FORCE:-0}" != 1 ]] && return

    echo "==> Building SDL_mixer"
    local dir="$SRC/onscripter_ios/SDL_mixer"
    local obj="$OUT/obj/SDL_mixer"
    mkdir -p "$obj"

    ( cd "$dir"
      for f in mixer.c music.c effects_internal.c effect_position.c \
               effect_stereoreverse.c load_aiff.c load_voc.c wavestream.c \
               music_ogg.c music_mad.c load_ogg.c dynamic_ogg.c; do
          "$CC" $CFLAGS -I. -I"$dir/../SDL/include" -I"$INC" \
              -DOGG_MUSIC -DOGG_USE_TREMOR -DMP3_MAD_MUSIC \
              -c "$f" -o "$obj/${f%.*}.o"
      done
      make_archive "$obj" SDL_mixer )

    cp "$obj/libSDL_mixer.a" "$LIB/"
    cp "$dir/SDL_mixer.h" "$INC/"
}

build_sdl_ttf() {
    [[ -f "$LIB/libSDL_ttf.a" && "${FORCE:-0}" != 1 ]] && return

    echo "==> Building SDL_ttf"
    local dir="$SRC/onscripter_ios/SDL_ttf"
    local obj="$OUT/obj/SDL_ttf"
    mkdir -p "$obj"

    ( cd "$dir"
      "$CC" $CFLAGS -I. -I"$dir/../SDL/include" -I"$INC" \
          -c SDL_ttf.c -o "$obj/SDL_ttf.o"
      make_archive "$obj" SDL_ttf )

    cp "$obj/libSDL_ttf.a" "$LIB/"
    cp "$dir/SDL_ttf.h" "$INC/"
}

download_sources
build_ogg
build_tremor
build_mad
build_freetype
build_jpeg
build_sdl
build_sdl_image
build_sdl_mixer
build_sdl_ttf

# Archives produced by the dependencies' own build systems may contain a GNU
# symbol table, which Darwin's linker does not understand.
for archive in "$LIB"/*.a; do
    "$RANLIB" "$archive"
done

echo
echo "Dependencies installed in $OUT"
ls -1 "$LIB"
