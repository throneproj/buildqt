@chcp 65001
@cd /d %~dp0

SET QT_VERSION=%1

CALL "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" amd64

SET QT_PATH=D:\a\buildqt\Qt

SET SRC_qtbase="%QT_PATH%\%QT_VERSION%\qtbase-everywhere-src-%QT_VERSION%"
SET SRC_qttools="%QT_PATH%\%QT_VERSION%\qttools-everywhere-src-%QT_VERSION%"
SET SRC_qttranslations="%QT_PATH%\%QT_VERSION%\qttranslations-everywhere-src-%QT_VERSION%"
SET SRC_qtsvg="%QT_PATH%\%QT_VERSION%\qtsvg-everywhere-src-%QT_VERSION%"

SET INSTALL_DIR="%QT_PATH%\Qt"
SET BUILD_DIR="%QT_PATH%\%QT_VERSION%\build"

rmdir /s /q "%BUILD_DIR%"
mkdir "%BUILD_DIR%" && cd /d "%BUILD_DIR%"

::qtbase
mkdir build-qtbase
cd build-qtbase
call %SRC_qtbase%\configure.bat -static -static-runtime -release -nomake examples -prefix %INSTALL_DIR% -opensource -confirm-license -qt-libpng -qt-libjpeg -qt-zlib -qt-pcre -qt-freetype -opengl desktop -platform win32-msvc -no-schannel -openssl-linked -no-dtls -no-ocsp -- -D OPENSSL_ROOT_DIR="%QT_PATH%/openssl"
cmake --build . --parallel
cmake --install .
cd ..

::qttools
mkdir build-qttools
cd build-qttools
cmake %SRC_qttools%\CMakeLists.txt -G "Ninja" -DCMAKE_INSTALL_PREFIX=%INSTALL_DIR% -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=%INSTALL_DIR%\lib\cmake"
cmake --build . --parallel
cmake --install .
cd ..

::qttranslations
mkdir build-qttranslations
cd build-qttranslations
cmake %SRC_qttranslations%\CMakeLists.txt -G "Ninja" -DCMAKE_INSTALL_PREFIX=%INSTALL_DIR% -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=%INSTALL_DIR%\lib\cmake"
cmake --build . --parallel
cmake --install .
cd ..

::qtsvg
mkdir build-qtsvg
cd build-qtsvg
cmake %SRC_qtsvg%\CMakeLists.txt -G "Ninja" -DCMAKE_INSTALL_PREFIX=%INSTALL_DIR% -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=%INSTALL_DIR%\lib\cmake"
cmake --build . --parallel
cmake --install .
cd ..

::@pause
@cmd /k cd /d %INSTALL_DIR%
