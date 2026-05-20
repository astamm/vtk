# rvtk 0.1.4

### New features

* **`use_rvtk()`: one-call downstream package setup.** A new
  [usethis](https://usethis.r-lib.org/)-style helper that configures a
  downstream R package to link against VTK in one step. Running
  `rvtk::use_rvtk()` inside a downstream package project:

  1. Adds `rvtk` to the `Imports` field of `DESCRIPTION`.
  2. Writes `src/Makevars` with backtick-style `Rscript` invocations that
     query `tools/configure.R` for compiler and linker flags.
  3. Writes `src/Makevars.win` with the Windows-specific `$(shell ...)` syntax
     that does the same.
  4. Writes `tools/configure.R` that calls `rvtk::CppFlags()` and
     `rvtk::LdFlagsFile()` with a customisable list of VTK modules.
  5. Adds `src/vtk_libs.rsp` to `.gitignore`.
  6. Creates `R/rvtk_imports.R` with a minimal `@importFrom rvtk` tag so
     that `R CMD check` does not warn about an unused `Imports` entry.

  The `modules` argument (default: the standard I/O + core set) lets
  downstream developers restrict linking to only the VTK modules they need,
  avoiding unintended symbol drag-in (important on macOS static bundles).

  Uses **cli** for formatted console output (listed in `Imports`).

* **Linux x86_64 musl (Alpine Linux) support.** The pre-built static fallback
  now provides a `vtk-X.Y.Z-linux-musl-x86_64.tar.gz` archive built inside an
  Alpine 3.22 container via `docker run` on the GitHub Actions runner (the
  `container:` job directive was not used because GitHub Actions' Node.js
  runtime is glibc-linked and crashes on musl). The `configure` script detects
  musl by inspecting `ldd --version` output and automatically downloads the
  correct archive; no user action is required. This fixes installation on the
  CRAN musl check platform (`x86_64-pc-linux-musl`, Alpine Linux).

  The following extra CMake flags are set for the musl build to avoid X11
  and rendering dependencies unavailable on the headless Alpine runner:
  `-DVTK_USE_X=OFF -DVTK_MODULE_ENABLE_VTK_RenderingOpenGL2=NO`.

* **Linux aarch64 support.** The pre-built static fallback now provides a
  `vtk-X.Y.Z-linux-aarch64.tar.gz` archive built on `ubuntu-24.04-arm`.
  The `configure` script detects the host architecture and downloads the
  correct archive automatically, so no user action is required.

### Bug fixes

* **`configure`: fixed `mktemp` incompatibility with BusyBox.** The
  temporary file for the pre-built archive download was created with a
  dotted suffix (`/tmp/vtk-prebuilt.XXXXXX.tar.gz`), which BusyBox `mktemp`
  rejects with `Invalid argument`. The suffix has been removed; the file is
  renamed internally before extraction.

* **`modules` argument for `LdFlags()` and `LdFlagsFile()`.**
  Both linker-flag functions now accept a `modules` character vector that
  restricts linking to the named VTK modules (e.g.
  `c("vtkIOLegacy", "vtkCommonCore")`).  When `NULL` (the default) all
  available modules are included, preserving backward compatibility.

  This is particularly important when using the pre-built static bundle on
  macOS: the bundle contains the full VTK (including rendering modules that
  reference `_NSEventTrackingRunLoopMode` from `AppKit.framework`).  Without
  filtering, `-Wl,-all_load` forces those symbols into every downstream `.so`,
  causing `dlopen()` failures at `R CMD check` time for packages that do not
  actually use any rendering functionality.  Downstream packages should pass
  only the modules they need:

  ```sh
  VTK_LIBS="$("${R_HOME}/bin/Rscript" --vanilla -e "rvtk::LdFlagsFile(
    path    = 'src/vtk_libs.rsp',
    modules = c('vtkIOLegacy', 'vtkCommonCore', ...)
  )")"
  ```

* New internal helper `filter_libs()` implements the module-name matching used
  by all three platform branches of `read_vtk_conf()`.

# rvtk 0.1.3

### New features

* **Windows VTK discovery** (`configure.win` rewritten). The package now
  searches for a system VTK installation on Windows before falling back to the
  pre-built libraries. Detection order:
  1. `VTK_DIR` environment variable.
  2. Rtools45 `pacman` (queries installed packages; never installs
     automatically).
  3. Common Rtools45 / MSYS2 prefixes (`/x86_64-w64-mingw32.static.posix`,
     `/ucrt64`, `/mingw64`, …).
  4. Automatic download of pre-built libraries (fallback — see below).
  Both static (`.a`) and shared (`.dll.a` import libs + DLLs) system
  installations are accepted.

* **Windows shared-DLL support** (`configure.win`, `tools/winlibs.R`,
  `R/vtk.R`, `R/zzz.R`). Windows now fully supports shared VTK libraries:
  - System or pacman/MSYS2 installations that provide `.dll.a` import libs are
    accepted and used directly.
  - A pre-built shared-DLL build (`vtk-X.Y.Z-shared-posix-x64.zip`) is
    available as an alternative to the existing static build. Select it by
    setting `VTK_LINK_TYPE=shared` before installing **rvtk** (default is
    `static`).
  - VTK DLLs are staged in rvtk's own `inst/vtk-dlls/`. An `.onLoad` hook
    prepends that directory to `PATH` via `Sys.setenv()` when rvtk is loaded,
    making the DLLs visible to all downstream packages that declare
    `Imports: rvtk` without any manual PATH manipulation. The original `PATH`
    is restored in `.onUnload()`. Downstream packages do **not** receive a copy
    of the DLLs — they piggyback on rvtk's staged directory at run time.

* **`build-vtk-libs.yml`**: new `build-windows-shared` CI job produces
  `vtk-X.Y.Z-shared-posix-x64.zip` alongside the existing static archive.

### Bug fixes

* **Unix pre-built static libraries survive `R CMD build`** (`configure`,
  `R/vtk.R`, `cleanup`). The pre-built archive is now extracted to
  `inst/prebuilt/` so that headers and static libraries ship inside the
  installed package. `read_vtk_conf()` resolves the actual paths at run time
  via `system.file("prebuilt", package = "rvtk")`, mirroring the Windows
  approach and surviving `R CMD build` temp-dir cycles.

### Internal

* Removed dead variable `lib_root` from `tools/winlibs.R` (assigned but
  never read).
* Removed dead variable `all_libs_full` from the Windows static branch of
  `read_vtk_conf()` in `R/vtk.R` (assigned but never read; `lib_flags` is
  built entirely from `-l` short names).
* New CI workflow (`.github/workflows/downstream-check.yaml`) builds and checks
  a minimal downstream package against rvtk across all supported platform ×
  VTK-strategy combinations (system, pre-built static, pre-built shared).

# rvtk 0.1.2

Re-submission addressing CRAN reviewer feedback on v0.1.1.

### Changes

* **DESCRIPTION:** Software names (`'VTK'`, `'Homebrew'`, `'pkg-config'`,
  `'Rtools45'`) are now consistently quoted with single quotes in the Title,
  Description, and SystemRequirements fields, per CRAN policy. Function calls
  such as `rvtk::CppFlags()` are no longer wrapped in single quotes.
* **`CppFlags()`, `LdFlags()`, `LdFlagsFile()`:** Replaced `cat()` with
  `writeLines()` and added `invisible()` returns so functions behave in a more
  idiomatic R style while still allowing shell command-substitution capture.
* **`tools/winlibs.R`:** The Windows VTK zip is now extracted to a temporary
  directory (`tempfile()`) before being copied into `inst/windows/`. This
  avoids writing intermediate files to the package source tree (home filespace)
  during installation.
* **Examples:** All exported functions now have small, executable `@examples`
  entries. `LdFlagsFile()` writes to `tempdir()` in its example.
* **Tests:** Test suite expanded to 100% line coverage of the non-platform-
  specific code paths on all platforms; Windows-specific branches
  (`LdFlagsFile()` response-file path, `read_vtk_conf()` Windows resolver) are
  exercised by the existing R-hub Windows CI jobs.

# rvtk 0.1.1

The planned CRAN submission of v0.1.0 was cancelled after downstream package
developers reported linker errors when building against the pre-built Windows
VTK libraries. Two root causes were identified and fixed:

1. **Wrong toolchain.** The Windows VTK zip was compiled with the Rtools45
   UCRT64 toolchain (`/ucrt64/bin/gcc`), which uses a dynamic C runtime and
   emits DLL-import symbols (`__imp_fseeko64`, `__imp_ftello64`, …). However,
   `R CMD INSTALL` links R packages with the `x86_64-w64-mingw32.static.posix`
   toolchain, which is fully static. The mismatch caused undefined references
   to `nanosleep64`, `ftime64`, `__imp_fseeko64`, and `__imp_ftello64`. The
   GitHub Actions workflow now builds the Windows VTK zip with the
   `x86_64-w64-mingw32.static.posix` compiler, matching the toolchain that
   downstream packages use.

2. **Command-line length overflow.** The full set of VTK `-l` linker flags
   exceeds the 8 191-character Windows command-line limit, causing the linker
   to silently drop flags at the end of the list. A new function
   `LdFlagsFile(path)` writes all flags to a response file and returns the
   short `@path` token that both GNU ld and LLVM lld support. Downstream
   packages should call `LdFlagsFile('src/vtk_libs.rsp')` from their
   `configure` / `configure.win` script instead of `LdFlags()`.

### Changes

* **New function** `LdFlagsFile(path)`: writes VTK linker flags to a response
  file and returns `@path` for use in `Makevars`. Preferred over `LdFlags()`
  on all platforms to avoid the Windows command-line length limit.
* Windows pre-built VTK libraries are now compiled with the
  `x86_64-w64-mingw32.static.posix` toolchain (Rtools45), matching the
  toolchain used by `R CMD INSTALL` for CRAN packages.
* Windows system libraries appended to `PKG_LIBS` reduced to `-lgdi32` only;
  the UCRT64-specific `-lwinpthread -lmingwex -lucrtbase` flags are no longer
  needed because the static.posix sysroot resolves POSIX symbols internally.
* README updated to document `LdFlagsFile()`, explain the rationale, provide
  a unified `configure` example valid on all platforms, and correct the Windows
  toolchain description.

# rvtk 0.1.0

* Initial CRAN submission.
* Bundles VTK 9.5.2 pre-built static libraries (`.a`) for Windows (Rtools45
  UCRT x64), macOS arm64, macOS x86_64, and Linux x86_64, distributed via
  GitHub Releases and built with GitHub Actions.
* VTK discovery strategy on macOS and Linux (in priority order):
  1. User-supplied `VTK_DIR` environment variable.
  2. Homebrew (macOS only).
  3. `pkg-config`.
  4. Well-known system prefixes (`/usr`, `/usr/local`) (Linux only).
  5. Automatic download of pre-built static libraries from
     <https://github.com/astamm/rvtk/releases> as a fallback.
* On Windows, pre-built UCRT64 static libraries are always downloaded
  automatically from <https://github.com/astamm/rvtk/releases>.
* **Windows limitation:** `netcdf` and `libproj` are not available in the
  Rtools45 UCRT64 environment. The following VTK modules are therefore
  disabled in the Windows pre-built libraries: `VTK_IONetCDF`, `VTK_IOHDF`,
  `VTK_GeovisCore`, `VTK_RenderingCore`. Downstream packages requiring these
  modules cannot be built on Windows with **rvtk**'s pre-built libraries.
* Downstream packages can retrieve compiler and linker flags via
  `rvtk::CppFlags()` and `rvtk::LdFlags()`.
