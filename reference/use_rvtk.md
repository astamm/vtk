# Set up a downstream package to use rvtk

A [usethis](https://usethis.r-lib.org/)-style helper that configures a
downstream R package to link against VTK via **rvtk**. It performs the
following steps:

- Adds `rvtk` to the `Imports` field of `DESCRIPTION`.

- Writes `src/Makevars` that queries compiler and linker flags at
  install time by calling `tools/configure.R`.

- Writes `src/Makevars.win` with the Windows-specific `$(shell ...)`
  syntax that does the same.

- Writes `tools/configure.R` that calls
  [`CppFlags()`](https://astamm.github.io/rvtk/reference/CppFlags.md)
  and
  [`LdFlagsFile()`](https://astamm.github.io/rvtk/reference/LdFlagsFile.md)
  with the requested VTK modules.

- Adds `src/vtk_libs.rsp` to `.gitignore` (it is generated at install
  time and must not be committed).

- Creates `R/rvtk_imports.R` with a minimal `@importFrom rvtk` roxygen
  tag so that `R CMD check` does not complain about **rvtk** being
  listed in `Imports` without any function import in the R code.

After running `use_rvtk()` the downstream package is fully configured:
VTK compiler and linker flags are resolved automatically at
`R CMD INSTALL` time on all platforms without any shell `configure` /
`configure.win` scripts.

## Usage

``` r
use_rvtk(
  modules = c("vtkIOLegacy", "vtkIOXML", "vtkIOXMLParser", "vtkIOCore", "vtkCommonCore",
    "vtkCommonDataModel", "vtkCommonExecutionModel", "vtkCommonMath", "vtkCommonMisc",
    "vtkCommonSystem", "vtkCommonTransforms", "vtksys"),
  path = "."
)
```

## Arguments

- modules:

  A character vector of VTK module names to link against. These are
  passed to
  [`LdFlagsFile()`](https://astamm.github.io/rvtk/reference/LdFlagsFile.md)
  in the generated `tools/configure.R`, restricting linking to only the
  modules the downstream package needs. Defaults to a standard set
  covering common I/O and core modules (the same set used by the
  reference implementation in <https://github.com/astamm/riot>).

- path:

  Path to the root of the downstream package. Defaults to the current
  working directory.

## Value

Invisibly, the normalised path to the package root. Called primarily for
its side effects.

## See also

[`CppFlags()`](https://astamm.github.io/rvtk/reference/CppFlags.md),
[`LdFlagsFile()`](https://astamm.github.io/rvtk/reference/LdFlagsFile.md)
