#!/bin/sh

set -u

status=0

echo "Limeghost CEF host readiness"
echo "Architecture: $(uname -m)"
sw_vers

if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version
else
  echo "MISSING: Xcode command-line tools"
  status=1
fi

if command -v cmake >/dev/null 2>&1; then
  cmake_version=$(cmake --version | sed -n '1p')
  echo "$cmake_version"
  cmake_major=$(echo "$cmake_version" | awk '{split($3, v, "."); print v[1]}')
  cmake_minor=$(echo "$cmake_version" | awk '{split($3, v, "."); print v[2]}')
  if [ "$cmake_major" -lt 3 ] || { [ "$cmake_major" -eq 3 ] && [ "$cmake_minor" -lt 21 ]; }; then
    echo "MISSING: CMake 3.21 or newer is required"
    status=1
  fi
else
  echo "MISSING: CMake 3.21 or newer"
  status=1
fi

if command -v python3 >/dev/null 2>&1; then
  python_version=$(python3 --version 2>&1)
  echo "$python_version"
  python_major=$(echo "$python_version" | awk '{split($2, v, "."); print v[1]}')
  python_minor=$(echo "$python_version" | awk '{split($2, v, "."); print v[2]}')
  if [ "$python_major" -ne 3 ] || [ "$python_minor" -lt 9 ] || [ "$python_minor" -gt 11 ]; then
    echo "UNTESTED: official cef-project setup currently documents Python 3.9 through 3.11"
    status=1
  fi
else
  echo "MISSING: Python 3.9 through 3.11 for the official cef-project setup"
  status=1
fi

if [ "${CEF_ROOT:-}" = "" ]; then
  echo "CEF_ROOT: not set (expected until the pinned archive is fetched and verified)"
else
  for required_path in \
    include/cef_app.h \
    cmake/FindCEF.cmake \
    libcef_dll/CMakeLists.txt \
    "Release/Chromium Embedded Framework.framework"; do
    if [ ! -e "$CEF_ROOT/$required_path" ]; then
      echo "MISSING: $CEF_ROOT/$required_path"
      status=1
    fi
  done
fi

if [ "$status" -eq 0 ]; then
  echo "READY: host prerequisites found"
else
  echo "NOT READY: see missing prerequisites above; nothing was installed or downloaded"
fi

exit "$status"
