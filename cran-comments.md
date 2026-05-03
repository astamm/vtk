## Submission (v0.1.3)

This is a new submission adding Windows VTK discovery, Windows shared-DLL
support, and fixing a path bug for pre-built static libraries on macOS/Linux.

### Changes since v0.1.2

1. **`configure.win` rewritten** — Windows now tries `VTK_DIR`, Rtools45
   `pacman`, and common MSYS2 prefixes before falling back to the pre-built
   libraries. Both static (`.a`) and shared (`.dll.a` + DLL) installations
   are accepted.

2. **Windows shared-DLL support** — System shared installations are now used
   directly. A new pre-built shared-DLL archive (`VTK_LINK_TYPE=shared`) is
   also available. VTK DLLs are staged in rvtk's `inst/vtk-dlls/`; an
   `.onLoad` hook prepends that directory to `PATH` so downstream packages
   need no extra configuration. Downstream packages do **not** receive a copy
   of the DLLs.

3. **`tools/vtk-detect.sh` added** — shared VTK prefix-detection helper
   sourced by both `configure` (macOS/Linux) and `configure.win` (Windows).

4. **Pre-built static path bug fixed** (macOS/Linux) — the pre-built archive
   is now extracted to `inst/prebuilt/` so headers and libs ship inside the
   installed package. Paths are resolved at run time via `system.file()`,
   matching the Windows approach and surviving `R CMD build` temp-dir cycles.

5. **Dead code removed** — `lib_root` in `tools/winlibs.R` and `all_libs_full`
   in the Windows static branch of `read_vtk_conf()` were assigned but never
   read; both removed.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Notes

* The package downloads pre-built VTK 9.5.2 libraries at install time from
  <https://github.com/astamm/rvtk/releases/tag/v9.5.2> when no suitable system
  VTK installation is found. This follows the established pattern used by
  packages such as 'curl', 'openssl', and 'rwinlib'-style packages.
* Pre-built binaries are provided for Windows ('Rtools45' static.posix x64,
  both static and shared builds), macOS arm64, macOS x86_64, and Linux x86_64.
  They are built reproducibly via GitHub Actions from the official VTK 9.5.2
  source tarball.
* No compiled code is included in the package itself (`NeedsCompilation: no`);
  all compilation happens either via the system VTK or the pre-built archives.

## Downstream usage

Downstream packages declare `Imports: rvtk` and use `rvtk::CppFlags()` /
`rvtk::LdFlagsFile()` in their `configure` / `configure.win` scripts to obtain
the correct compiler and linker flags for the detected or downloaded VTK
installation.

---

## Re-submission (v0.1.2)

This is a re-submission addressing all points raised by the CRAN reviewer on
v0.1.1.

### Reviewer points addressed

1. **Software-name quoting in DESCRIPTION** — `'VTK'`, `'Homebrew'`,
   `'pkg-config'`, and `'Rtools45'` are now in single quotes throughout the
   Title, Description, and SystemRequirements fields. Function calls such as
   `rvtk::CppFlags()` are no longer wrapped in single quotes.

2. **`cat()`/`print()` in exported functions** — `cat()` calls in `CppFlags()`,
   `LdFlags()`, and `LdFlagsFile()` have been replaced with `writeLines()`.
   All three functions now return their value `invisible()`-y, so the output
   can be suppressed by callers while still being captured by shell
   command-substitution (`$(Rscript -e ...)`).

3. **Writing to home filespace in `tools/winlibs.R`** — The Windows VTK zip is
   now extracted to a `tempfile()` directory first and then copied into
   `inst/windows/`. No files are written to the package source directory or
   `getwd()` during the extraction step.

4. **Executable examples** — All four exported functions (`CppFlags()`,
   `LdFlags()`, `LdFlagsFile()`, `VtkVersion()`) now have `@examples` entries.
   `LdFlagsFile()` writes to `tempdir()`.

5. **Tests** — The `tinytest` suite now covers all reachable code paths on the
   test platform, including both branches of `LdFlagsFile()` (the Windows
   response-file branch is conditionally exercised on Windows CI via R-hub).

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Notes

* The package downloads pre-built VTK 9.5.2 static libraries at install time
  from <https://github.com/astamm/rvtk/releases/tag/v9.5.2> in two cases:
  (a) always on Windows, and (b) on macOS/Linux when no suitable system VTK
  installation is detected. This follows the established pattern used by
  packages such as 'curl', 'openssl', and 'rwinlib'-style packages.
* Pre-built binaries are provided for Windows ('Rtools45' static.posix x64),
  macOS arm64, macOS x86_64, and Linux x86_64. They are built reproducibly via
  GitHub Actions from the official VTK 9.5.2 source tarball.
* No compiled code is included in the package itself (`NeedsCompilation: no`);
  all compilation happens either via the system VTK or the pre-built archives.

## Downstream usage

Downstream packages declare `Imports: rvtk` and use `rvtk::CppFlags()` /
`rvtk::LdFlagsFile()` in their `configure` / `configure.win` scripts to obtain
the correct compiler and linker flags for the detected or downloaded VTK
installation.
