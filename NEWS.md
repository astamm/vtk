# rvtk 0.1.3

### New features

* **Windows VTK discovery** (`configure.win` rewritten). The package now
  searches for a system VTK installation on Windows before falling back to the
  pre-built static libraries. Detection order:
  1. `VTK_DIR` environment variable.
  2. Rtools45 `pacman` (queries installed packages; never installs
     automatically).
  3. Common Rtools45 / MSYS2 prefixes (`/x86_64-w64-mingw32.static.posix`,
     `/ucrt64`, `/mingw64`, …).
  4. Automatic download of pre-built static libraries (unchanged fallback).
  Only static `.a` archives are used; DLL-backed `.dll.a` import libraries are
  explicitly excluded. A system VTK that provides only shared libraries is
  therefore skipped and the pre-built fallback is used instead.

* **Shared VTK detection helper** (`tools/vtk-detect.sh`). The
  prefix-detection logic is now in a single sourced shell script used by both
  `configure` (macOS/Linux) and `configure.win` (Windows), ensuring consistent
  versioned-directory detection on all platforms.

### Bug fixes

* **Unix pre-built static libraries survive `R CMD build`** (`configure`,
  `R/vtk.R`, `cleanup`). Previously the pre-built archive was extracted to
  `$(pwd)/vtk-prebuilt/` at configure time; because `pak` / `R CMD build`
  creates a source tarball in a temporary directory, these paths became
  dangling after installation. The archive is now extracted to
  `inst/prebuilt/` so that headers and static libraries ship inside the
  installed package. `read_vtk_conf()` resolves the actual paths at run time
  via `system.file("prebuilt", package = "rvtk")`, mirroring the approach
  already used for Windows.

### Internal

* New CI workflow (`.github/workflows/downstream-check.yaml`) builds and
  checks a minimal downstream package against rvtk across all supported
  platform × VTK-strategy combinations (system, pre-built static, built
  shared).

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
