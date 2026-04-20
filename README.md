
<!-- README.md is generated from README.Rmd. Please edit that file -->

# rvtk

<!-- badges: start -->

[![R-CMD-check](https://github.com/astamm/rvtk/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/astamm/rvtk/actions/workflows/R-CMD-check.yaml)
[![Codecov test
coverage](https://codecov.io/gh/astamm/rvtk/graph/badge.svg)](https://app.codecov.io/gh/astamm/rvtk)
<!-- badges: end -->

**rvtk** is an infrastructure package that makes the [Visualization
Toolkit (VTK)](https://vtk.org/) available to other R packages that need
to link against it. It provides four utility functions — `CppFlags()`,
`LdFlags()`, `LdFlagsFile()`, and `VtkVersion()` — that return the
correct compiler and linker flags for however VTK was found or installed
on the current machine.

## How VTK is located

On macOS and Linux the package runs a `configure` script at install time
that tries each of the following strategies in order, stopping as soon
as one succeeds:

1.  The environment variable `VTK_DIR` (path to a VTK build or install
    tree).
2.  [Homebrew](https://brew.sh/) (`brew --prefix vtk`).
3.  `pkg-config` (`vtk-9.5`, `vtk-9.4`, …, `vtk-9.1`).
4.  Common system prefixes (`/usr/local`, `/usr`, `/opt/local`).
5.  Download pre-built static libraries from
    <https://github.com/astamm/rvtk/releases>.

On Windows, pre-built static libraries (built with the
`x86_64-w64-mingw32.static.posix` toolchain bundled in Rtools45) are
always downloaded automatically from the same URL.

> **Windows limitation:** The Rtools45 `static.posix` sysroot does not
> provide `netcdf` or `libproj`. Consequently, the following VTK modules
> are **disabled** in the Windows pre-built libraries: `VTK_IONetCDF`,
> `VTK_IOHDF`, `VTK_GeovisCore`, `VTK_RenderingCore`. Downstream
> packages that require any of these modules cannot currently be built
> on Windows with the pre-built libraries supplied by **rvtk**.

Configuration results are stored in `inst/vtk.conf` and read at run time
by `CppFlags()`, `LdFlags()`, and `VtkVersion()`.

## Installation

``` r
# install.packages("pak")
pak::pak("astamm/rvtk")
```

A system VTK installation (≥ 9.1.0) is not required: if none is found
the package downloads pre-built static libraries automatically.

## Usage for downstream package developers

Add **rvtk** to the `Imports` field of your `DESCRIPTION`:

    Imports: rvtk

Because `$(shell ...)` is a GNU make extension that is **not** allowed
in `Makevars`, the correct approach is to query `rvtk::CppFlags()` and
`rvtk::LdFlagsFile()` from a `configure` / `configure.win` script and
write the results into `src/Makevars` at install time.

`LdFlagsFile()` is preferred over `LdFlags()` for the linker flags
because the full set of VTK `-l` flags can exceed the 8 191-character
Windows command-line limit, which causes the linker to silently drop
flags at the end of the list. `LdFlagsFile(path)` writes the flags to a
response file and returns `@path` — the short token the linker reads
instead. GNU ld and LLVM lld both support this syntax. On macOS and
Linux the flags are also written to the file so the calling convention
is identical on all platforms.

### Step 1 — `src/Makevars.in` (template, committed to version control)

``` makefile
PKG_CPPFLAGS = @VTK_CPPFLAGS@
PKG_LIBS     = @VTK_LIBS@
```

### Step 2 — `configure`(`.win`)

``` sh
# configure (macOS/Linux/Windows)
#!/bin/sh
set -e
: "${R_HOME:=$(R RHOME)}"
VTK_CPPFLAGS="$("${R_HOME}/bin/Rscript" --vanilla -e "rvtk::CppFlags()")"
# LdFlagsFile() writes all linker flags to a response file (src/vtk_libs.rsp)
# and returns the short token @vtk_libs.rsp that is safe on all platforms,
# including Windows where the full flag string can exceed the 8191-char limit.
VTK_LIBS="$("${R_HOME}/bin/Rscript" --vanilla -e "rvtk::LdFlagsFile('src/vtk_libs.rsp')")"
sed -e "s|@VTK_CPPFLAGS@|${VTK_CPPFLAGS}|g" \
    -e "s|@VTK_LIBS@|${VTK_LIBS}|g" \
    src/Makevars.in > src/Makevars
```

``` sh
# configure.win (Windows)
#!/bin/sh
./configure
```

Make them executable:

``` sh
chmod +x configure configure.win
```

### Step 3 — `.gitignore` / `.Rbuildignore`

Add the generated files to `.gitignore` so they are not committed:

    src/Makevars
    src/vtk_libs.rsp

### Step 4 - `cleanup`(`.win`)

Add a `cleanup` / `cleanup.win` script that removes the generated
`Makevars` after installation so it is not accidentally committed:

``` sh
# cleanup (macOS/Linux/Windows)
#!/bin/sh
rm -f src/Makevars src/vtk_libs.rsp
```

``` sh
# cleanup.win (Windows)
#!/bin/sh
./cleanup
```

Make them executable:

``` sh
chmod +x cleanup cleanup.win
```

### Step 5 - Function import

The **rvtk** package is meant to be used by downstream packages that
link against VTK. It is most likely that its R functions will only be
called from `configure` / `configure.win` scripts. `R CMD check` will
complain because it means that you must list **rvtk** in the `Imports`
field of your `DESCRIPTION` but do not actually import any of its
functions in your R code. The solution is to import at least one of the
functions in a dummy R script that is not used for anything else:

``` r
# R/rvtk_imports.R
#' @importFrom rvtk CppFlags LdFlagsFile
NULL
```

## Querying the detected installation

You can verify the detected installation at any time:

``` r
library(rvtk)
CppFlags()
#> -isystem/opt/homebrew/opt/vtk/include/vtk-9.5
LdFlagsFile(tempfile(fileext = ".rsp"))
#> -L/opt/homebrew/opt/vtk/lib -lvtkIOLegacy-9.5 -lvtkIOXML-9.5 -lvtkIOXMLParser-9.5 -lvtkIOCore-9.5 -lvtkCommonCore-9.5 -lvtkCommonDataModel-9.5 -lvtkCommonExecutionModel-9.5 -lvtkCommonMath-9.5 -lvtkCommonMisc-9.5 -lvtkCommonSystem-9.5 -lvtkCommonTransforms-9.5 -lvtksys-9.5
VtkVersion()
#> [1] "9.5.0"
```
