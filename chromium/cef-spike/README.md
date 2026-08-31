# Limeghost CEF spike

This directory is an **isolated Chromium migration scaffold**. It is not linked into `macos/LimeghostBrowser`, does not alter `dist/Limeghost.app`, and does not contain a working browser implementation.

The selected engine path is the Chromium Embedded Framework (CEF) with:

- official architecture-specific binary distributions;
- CMake/Xcode for the CEF native wrapper and macOS app/helper bundle;
- a thin Limeghost-owned Objective-C++ implementation behind the Objective-C contract in `include/LimeghostChromiumBridge.h`;
- the existing SwiftUI product UI and `LimeghostCore` above that bridge.

Read [the migration plan](../../docs/chromium-migration.md) before extending this spike.

## Safe host check

```bash
./scripts/validate-host.sh
```

This checks the local architecture, Xcode command-line tools, CMake version, and an optional `CEF_ROOT`. It never installs or downloads anything.

## Configure-only scaffold check

CEF's official CMake workflow requires CMake 3.21 or newer. With no CEF archive present, validate only the project boundary:

```bash
cmake -S . -B build -G Xcode \
  -DLIMEGHOST_CEF_VALIDATE_ONLY=ON \
  -DPROJECT_ARCH=arm64
```

After separately downloading and verifying the pinned official distribution, extract it outside source control and point `CEF_ROOT` at its root:

```bash
cmake -S . -B build -G Xcode \
  -DLIMEGHOST_CEF_VALIDATE_ONLY=OFF \
  -DPROJECT_ARCH=arm64 \
  -DCEF_ROOT=/absolute/path/to/cef_binary_distribution
```

The non-validation configuration loads CEF's official `FindCEF.cmake` and includes `libcef_dll_wrapper`. It deliberately does not create or package a Limeghost runtime target yet. The next implementation should begin from official `cefsimple` and preserve its macOS helper-process structure.

Do not commit a downloaded CEF distribution, build products, or a copied Chromium framework to this repository.
