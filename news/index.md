# Changelog

## rvtk (development version)

## rvtk 0.1.3

CRAN release: 2026-05-11

#### New features

- **Windows VTK discovery** (`configure.win` rewritten). The package now
  searches for a system VTK installation on Windows before falling back
  to the pre-built libraries. Detection order:
  1.  `VTK_DIR` environment variable.
  2.  Rtools45 `pacman` (queries installed packages; never installs
      automatically).
  3.  Common Rtools45 / MSYS2 prefixes
      (`/x86_64-w64-mingw32.static.posix`, `/ucrt64`, `/mingw64`, …).
  4.  Automatic download of pre-built libraries (fallback — see below).
      Both static (`.a`) and shared (`.dll.a` import libs + DLLs) system
      installations are accepted.
- **Windows shared-DLL support** (`configure.win`, `tools/winlibs.R`,
  `R/vtk.R`, `R/zzz.R`). Windows now fully supports shared VTK
  libraries:
  - System or pacman/MSYS2 installations that provide `.dll.a` import
    libs are accepted and used directly.
  - A pre-built shared-DLL build (`vtk-X.Y.Z-shared-posix-x64.zip`) is
    available as an alternative to the existing static build. Select it
    by setting `VTK_LINK_TYPE=shared` before installing **rvtk**
    (default is `static`).
  - VTK DLLs are staged in rvtk’s own `inst/vtk-dlls/`. An `.onLoad`
    hook prepends that directory to `PATH` via
    [`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html) when rvtk
    is loaded, making the DLLs visible to all downstream packages that
    declare `Imports: rvtk` without any manual PATH manipulation. The
    original `PATH` is restored in `.onUnload()`. Downstream packages do
    **not** receive a copy of the DLLs — they piggyback on rvtk’s staged
    directory at run time.
- **`build-vtk-libs.yml`**: new `build-windows-shared` CI job produces
  `vtk-X.Y.Z-shared-posix-x64.zip` alongside the existing static
  archive.

#### Bug fixes

- **Unix pre-built static libraries survive `R CMD build`**
  (`configure`, `R/vtk.R`, `cleanup`). The pre-built archive is now
  extracted to `inst/prebuilt/` so that headers and static libraries
  ship inside the installed package. `read_vtk_conf()` resolves the
  actual paths at run time via
  `system.file("prebuilt", package = "rvtk")`, mirroring the Windows
  approach and surviving `R CMD build` temp-dir cycles.

#### Internal

- Removed dead variable `lib_root` from `tools/winlibs.R` (assigned but
  never read).
- Removed dead variable `all_libs_full` from the Windows static branch
  of `read_vtk_conf()` in `R/vtk.R` (assigned but never read;
  `lib_flags` is built entirely from `-l` short names).
- New CI workflow (`.github/workflows/downstream-check.yaml`) builds and
  checks a minimal downstream package against rvtk across all supported
  platform × VTK-strategy combinations (system, pre-built static,
  pre-built shared).

## rvtk 0.1.2

Re-submission addressing CRAN reviewer feedback on v0.1.1.

#### Changes

- **DESCRIPTION:** Software names (`'VTK'`, `'Homebrew'`,
  `'pkg-config'`, `'Rtools45'`) are now consistently quoted with single
  quotes in the Title, Description, and SystemRequirements fields, per
  CRAN policy. Function calls such as
  [`rvtk::CppFlags()`](https://astamm.github.io/rvtk/reference/CppFlags.md)
  are no longer wrapped in single quotes.
- **[`CppFlags()`](https://astamm.github.io/rvtk/reference/CppFlags.md),
  [`LdFlags()`](https://astamm.github.io/rvtk/reference/LdFlags.md),
  [`LdFlagsFile()`](https://astamm.github.io/rvtk/reference/LdFlagsFile.md):**
  Replaced [`cat()`](https://rdrr.io/r/base/cat.html) with
  [`writeLines()`](https://rdrr.io/r/base/writeLines.html) and added
  [`invisible()`](https://rdrr.io/r/base/invisible.html) returns so
  functions behave in a more idiomatic R style while still allowing
  shell command-substitution capture.
- **`tools/winlibs.R`:** The Windows VTK zip is now extracted to a
  temporary directory
  ([`tempfile()`](https://rdrr.io/r/base/tempfile.html)) before being
  copied into `inst/windows/`. This avoids writing intermediate files to
  the package source tree (home filespace) during installation.
- **Examples:** All exported functions now have small, executable
  `@examples` entries.
  [`LdFlagsFile()`](https://astamm.github.io/rvtk/reference/LdFlagsFile.md)
  writes to [`tempdir()`](https://rdrr.io/r/base/tempfile.html) in its
  example.
- **Tests:** Test suite expanded to 100% line coverage of the
  non-platform- specific code paths on all platforms; Windows-specific
  branches
  ([`LdFlagsFile()`](https://astamm.github.io/rvtk/reference/LdFlagsFile.md)
  response-file path, `read_vtk_conf()` Windows resolver) are exercised
  by the existing R-hub Windows CI jobs.

## rvtk 0.1.1

The planned CRAN submission of v0.1.0 was cancelled after downstream
package developers reported linker errors when building against the
pre-built Windows VTK libraries. Two root causes were identified and
fixed:

1.  **Wrong toolchain.** The Windows VTK zip was compiled with the
    Rtools45 UCRT64 toolchain (`/ucrt64/bin/gcc`), which uses a dynamic
    C runtime and emits DLL-import symbols (`__imp_fseeko64`,
    `__imp_ftello64`, …). However, `R CMD INSTALL` links R packages with
    the `x86_64-w64-mingw32.static.posix` toolchain, which is fully
    static. The mismatch caused undefined references to `nanosleep64`,
    `ftime64`, `__imp_fseeko64`, and `__imp_ftello64`. The GitHub
    Actions workflow now builds the Windows VTK zip with the
    `x86_64-w64-mingw32.static.posix` compiler, matching the toolchain
    that downstream packages use.

2.  **Command-line length overflow.** The full set of VTK `-l` linker
    flags exceeds the 8 191-character Windows command-line limit,
    causing the linker to silently drop flags at the end of the list. A
    new function `LdFlagsFile(path)` writes all flags to a response file
    and returns the short `@path` token that both GNU ld and LLVM lld
    support. Downstream packages should call
    `LdFlagsFile('src/vtk_libs.rsp')` from their `configure` /
    `configure.win` script instead of
    [`LdFlags()`](https://astamm.github.io/rvtk/reference/LdFlags.md).

#### Changes

- **New function** `LdFlagsFile(path)`: writes VTK linker flags to a
  response file and returns `@path` for use in `Makevars`. Preferred
  over [`LdFlags()`](https://astamm.github.io/rvtk/reference/LdFlags.md)
  on all platforms to avoid the Windows command-line length limit.
- Windows pre-built VTK libraries are now compiled with the
  `x86_64-w64-mingw32.static.posix` toolchain (Rtools45), matching the
  toolchain used by `R CMD INSTALL` for CRAN packages.
- Windows system libraries appended to `PKG_LIBS` reduced to `-lgdi32`
  only; the UCRT64-specific `-lwinpthread -lmingwex -lucrtbase` flags
  are no longer needed because the static.posix sysroot resolves POSIX
  symbols internally.
- README updated to document
  [`LdFlagsFile()`](https://astamm.github.io/rvtk/reference/LdFlagsFile.md),
  explain the rationale, provide a unified `configure` example valid on
  all platforms, and correct the Windows toolchain description.

## rvtk 0.1.0

- Initial CRAN submission.
- Bundles VTK 9.5.2 pre-built static libraries (`.a`) for Windows
  (Rtools45 UCRT x64), macOS arm64, macOS x86_64, and Linux x86_64,
  distributed via GitHub Releases and built with GitHub Actions.
- VTK discovery strategy on macOS and Linux (in priority order):
  1.  User-supplied `VTK_DIR` environment variable.
  2.  Homebrew (macOS only).
  3.  `pkg-config`.
  4.  Well-known system prefixes (`/usr`, `/usr/local`) (Linux only).
  5.  Automatic download of pre-built static libraries from
      <https://github.com/astamm/rvtk/releases> as a fallback.
- On Windows, pre-built UCRT64 static libraries are always downloaded
  automatically from <https://github.com/astamm/rvtk/releases>.
- **Windows limitation:** `netcdf` and `libproj` are not available in
  the Rtools45 UCRT64 environment. The following VTK modules are
  therefore disabled in the Windows pre-built libraries: `VTK_IONetCDF`,
  `VTK_IOHDF`, `VTK_GeovisCore`, `VTK_RenderingCore`. Downstream
  packages requiring these modules cannot be built on Windows with
  **rvtk**’s pre-built libraries.
- Downstream packages can retrieve compiler and linker flags via
  [`rvtk::CppFlags()`](https://astamm.github.io/rvtk/reference/CppFlags.md)
  and
  [`rvtk::LdFlags()`](https://astamm.github.io/rvtk/reference/LdFlags.md).
