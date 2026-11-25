#!/bin/bash
set -euo pipefail

: "${QT_VERSION:?QT_VERSION is not set}"
: "${OPENSSL_VERSION:?OPENSSL_VERSION is not set}"
QT_PATH="${QT_PATH:-$(cd "${GITHUB_WORKSPACE:?}/../Qt" && pwd)}"

SRC_qtbase="$QT_PATH/$QT_VERSION/qtbase-everywhere-src-$QT_VERSION"
SRC_qtsvg="$QT_PATH/$QT_VERSION/qtsvg-everywhere-src-$QT_VERSION"
SRC_qtwayland="$QT_PATH/$QT_VERSION/qtwayland-everywhere-src-$QT_VERSION"
SRC_qttools="$QT_PATH/$QT_VERSION/qttools-everywhere-src-$QT_VERSION"
SRC_openssl="$QT_PATH/$QT_VERSION/openssl-$OPENSSL_VERSION"

INSTALL_DIR="$QT_PATH/Qt"
OPENSSL_DIR="$QT_PATH/openssl"
BUILD_DIR="$QT_PATH/$QT_VERSION/build"

# OpenSSL ends up static in both QtNetwork (QPasswordDigestor's PBKDF2) and the TLS plugin; keep it out of their dynamic symbols.
EXCLUDE_OPENSSL="-Wl,--exclude-libs,libssl.a:libcrypto.a"

gcc --version | head -n1
cmake --version | head -n1
echo "ninja $(ninja --version)"

rm -rf "$BUILD_DIR" "$OPENSSL_DIR"
mkdir -p "$BUILD_DIR"

build_module() {
    local name=$1 src=$2
    shift 2
    mkdir "$BUILD_DIR/$name"
    cd "$BUILD_DIR/$name"
    cmake -S "$src" -B . -G Ninja -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$INSTALL_DIR/lib/cmake" -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DQT_GENERATE_SBOM=OFF "$@"
    cmake --build . --parallel
    cmake --install . --strip
}

#openssl
mkdir "$BUILD_DIR/openssl"
cd "$BUILD_DIR/openssl"
"$SRC_openssl/Configure" no-shared no-tests -fPIC --prefix="$OPENSSL_DIR" --openssldir=/etc/ssl --libdir=lib
make -j"$(nproc)" build_sw
make install_sw

#qtbase
# Qt 6.8+ builds localized time-zone names into QtCore (~4 MB); Throne never shows them.
TZ_LOCALE=""
IFS=. read -r QT_MAJOR QT_MINOR _ <<<"$QT_VERSION"
if (( QT_MAJOR * 100 + QT_MINOR >= 608 )); then TZ_LOCALE="-no-feature-timezone_locale"; fi
mkdir "$BUILD_DIR/qtbase"
cd "$BUILD_DIR/qtbase"
"$SRC_qtbase/configure" -prefix "$INSTALL_DIR" -release -shared -opensource -confirm-license \
    -nomake examples -nomake tests -no-sbom -cmake-generator Ninja \
    -no-icu -glib -dbus-linked -gtk -xcb -xkbcommon -feature-wayland -opengl desktop -egl \
    -fontconfig -system-freetype -system-zlib -qt-libpng -qt-libjpeg -qt-pcre -qt-harfbuzz -qt-doubleconversion \
    -openssl-linked -no-feature-openssl-hash -no-feature-gssapi -no-feature-brotli -no-zstd \
    -no-feature-xcb-sm -no-feature-wayland-server $TZ_LOCALE \
    -- -DOPENSSL_ROOT_DIR="$OPENSSL_DIR" -DOPENSSL_USE_STATIC_LIBS=ON \
    -DCMAKE_MODULE_LINKER_FLAGS="$EXCLUDE_OPENSSL" -DCMAKE_SHARED_LINKER_FLAGS="$EXCLUDE_OPENSSL" \
    -DOpenGL_GL_PREFERENCE=LEGACY
cmake --build . --parallel
cmake --install . --strip

#qtsvg
build_module qtsvg "$SRC_qtsvg"

#qtwayland
build_module qtwayland "$SRC_qtwayland" -DFEATURE_wayland_decoration_adwaita=ON

#qttools
build_module qttools "$SRC_qttools" -DFEATURE_linguist=ON -DFEATURE_assistant=OFF -DFEATURE_designer=OFF \
    -DFEATURE_distancefieldgenerator=OFF -DFEATURE_kmap2qmap=OFF -DFEATURE_pixeltool=OFF -DFEATURE_qdbus=OFF \
    -DFEATURE_qev=OFF -DFEATURE_qtattributionsscanner=OFF -DFEATURE_qtdiag=OFF -DFEATURE_qtplugininfo=OFF \
    -DFEATURE_qdoc=OFF -DFEATURE_clang=OFF

#xcb-cursor
cp -a /usr/lib64/libxcb-cursor.so.0* /usr/lib64/libxcb-util.so.1* "$INSTALL_DIR/lib/"
# Lets libxcb-cursor find the bundled libxcb-util; RUNPATH of the Qt libs does not cover transitive dependencies.
patchelf --set-rpath '$ORIGIN' "$(readlink -f "$INSTALL_DIR/lib/libxcb-cursor.so.0")"
