#!/bin/bash
set -euo pipefail
export LC_ALL=C

usage="usage: checkqt_linux.sh files|openssl|floors <qt-dir>"
MODE=${1:?$usage}
QT_DIR=${2:?$usage}
QT_DIR=$(cd "$QT_DIR" && pwd)

MAX_GLIBC=2.28
MAX_GLIBCXX=3.4.25
MAX_CXXABI=1.3.11

REQUIRED=(
    lib/libQt6Core.so.6 lib/libQt6Gui.so.6 lib/libQt6Widgets.so.6 lib/libQt6Network.so.6
    lib/libQt6DBus.so.6 lib/libQt6Svg.so.6 lib/libQt6XcbQpa.so.6 lib/libQt6WaylandClient.so.6
    lib/libxcb-cursor.so.0 lib/libxcb-util.so.1
    plugins/platforms/libqxcb.so plugins/platforms/libqwayland.so
    plugins/platformthemes/libqgtk3.so plugins/platformthemes/libqxdgdesktopportal.so
    plugins/imageformats/libqgif.so plugins/imageformats/libqico.so plugins/imageformats/libqjpeg.so
    plugins/imageformats/libqsvg.so plugins/iconengines/libqsvgicon.so
    plugins/tls/libqopensslbackend.so plugins/tls/libqcertonlybackend.so
    plugins/wayland-decoration-client/libadwaita.so plugins/wayland-decoration-client/libbradient.so
    bin/lrelease bin/lupdate bin/lconvert libexec/moc libexec/rcc libexec/uic
    lib/cmake/Qt6/Qt6Config.cmake lib/cmake/Qt6LinguistTools/Qt6LinguistToolsConfig.cmake
)

is_elf() {
    local magic=''
    IFS= read -r -n 4 -d '' magic < "$1" || true
    [ "$magic" = $'\x7fELF' ]
}

ELFS=()
while IFS= read -r -d '' f; do
    if is_elf "$f"; then ELFS+=("$f"); fi
done < <(find "$QT_DIR" -type f -print0 | sort -z)
if [ ${#ELFS[@]} -eq 0 ]; then
    echo "no ELF files under $QT_DIR" >&2
    exit 1
fi

max_ver() {
    { grep -o "$1_[0-9][0-9.]*" || true; } | sed "s/^$1_//" | sort -uV | tail -n1
}

ver_gt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

check_files() {
    local fail=0 p
    for p in "${REQUIRED[@]}"; do
        if [ -e "$QT_DIR/$p" ]; then
            echo "ok      $p"
        else
            echo "MISSING $p"
            fail=1
        fi
    done
    if compgen -G "$QT_DIR/plugins/wayland-shell-integration/*.so" > /dev/null; then
        echo "ok      plugins/wayland-shell-integration/*.so"
    else
        echo "MISSING plugins/wayland-shell-integration/*.so"
        fail=1
    fi
    return $fail
}

check_openssl() {
    local fail=0 f plugin="$QT_DIR/plugins/tls/libqopensslbackend.so" exported
    : "${OPENSSL_VERSION:?OPENSSL_VERSION is not set}"
    for f in "${ELFS[@]}"; do
        if readelf -d -W "$f" | grep -E '\(NEEDED\).*\[lib(ssl|crypto)\.so'; then
            echo "${f#"$QT_DIR"/} needs a shared OpenSSL"
            fail=1
        fi
    done
    if grep -a -q "OpenSSL $OPENSSL_VERSION " "$plugin"; then
        echo "${plugin#"$QT_DIR"/} embeds OpenSSL $OPENSSL_VERSION"
    else
        echo "${plugin#"$QT_DIR"/} does not embed OpenSSL $OPENSSL_VERSION"
        fail=1
    fi
    exported=$(nm -D --defined-only "$plugin" "$QT_DIR/lib/libQt6Network.so.6" \
        | grep -E ' [A-Za-z] (SSL|EVP|OPENSSL|OSSL|CRYPTO|X509|BIO|ERR|d2i|i2d)_' || true)
    if [ -n "$exported" ]; then
        echo "OpenSSL symbols are exported:"
        echo "$exported" | head -n 20
        fail=1
    fi
    return $fail
}

check_floors() {
    local fail=0 f v g x a odd bad all_g=() all_x=() all_a=() n
    declare -A needed=()
    for f in "${ELFS[@]}"; do
        v=$(readelf -V -W "$f")
        g=$(max_ver GLIBC <<< "$v")
        x=$(max_ver GLIBCXX <<< "$v")
        a=$(max_ver CXXABI <<< "$v")
        odd=$({ grep -o 'GLIBC_[A-Z][A-Z_]*' <<< "$v" || true; } | sort -u | tr '\n' ' ')
        bad=""
        if [ -n "$g" ] && ver_gt "$g" "$MAX_GLIBC"; then bad+=" GLIBC_$g"; fi
        if [ -n "$x" ] && ver_gt "$x" "$MAX_GLIBCXX"; then bad+=" GLIBCXX_$x"; fi
        if [ -n "$a" ] && ver_gt "$a" "$MAX_CXXABI"; then bad+=" CXXABI_$a"; fi
        if [ -n "$odd" ]; then bad+=" $odd"; fi
        printf '%-80s GLIBC_%-6s GLIBCXX_%-8s CXXABI_%-7s%s\n' "${f#"$QT_DIR"/}" "${g:--}" "${x:--}" "${a:--}" \
            "${bad:+  exceeds:$bad}"
        if [ -n "$bad" ]; then fail=1; fi
        if [ -n "$g" ]; then all_g+=("$g"); fi
        if [ -n "$x" ]; then all_x+=("$x"); fi
        if [ -n "$a" ]; then all_a+=("$a"); fi
        while IFS= read -r n; do
            needed[$n]=1
        done < <(readelf -d -W "$f" | sed -n 's/.*(NEEDED).*\[\(.*\)\]$/\1/p')
    done
    echo
    echo "Highest overall: GLIBC_$(printf '%s\n' "${all_g[@]}" | sort -V | tail -n1)" \
        "GLIBCXX_$(printf '%s\n' "${all_x[@]}" | sort -V | tail -n1)" \
        "CXXABI_$(printf '%s\n' "${all_a[@]}" | sort -V | tail -n1)" \
        "(limits GLIBC_$MAX_GLIBC GLIBCXX_$MAX_GLIBCXX CXXABI_$MAX_CXXABI)"
    echo "System libraries needed:"
    printf '%s\n' "${!needed[@]}" | { grep -v '^libQt6' || true; } | sort | sed 's/^/  /'
    return $fail
}

case "$MODE" in
    files) check_files ;;
    openssl) check_openssl ;;
    floors) check_floors ;;
    *) echo "$usage" >&2; exit 2 ;;
esac
