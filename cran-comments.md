## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Notes

* The package downloads pre-built VTK 9.5.2 static libraries at install time
  from <https://github.com/astamm/rvtk/releases/tag/v9.5.2> in two cases:
  (a) always on Windows, and (b) on macOS/Linux when no suitable system VTK
  installation is detected. This follows the established pattern used by
  packages such as 'curl', 'openssl', and 'rwinlib'-style packages.
* Pre-built binaries are provided for Windows (Rtools45 static.posix x64), macOS
  arm64, macOS x86_64, and Linux x86_64. They are built reproducibly via
  GitHub Actions from the official VTK 9.5.2 source tarball.
* No compiled code is included in the package itself (`NeedsCompilation: no`);
  all compilation happens either via the system VTK or the pre-built archives.

## Downstream usage

Downstream packages declare `Imports: rvtk` and use `rvtk::CppFlags()` /
`rvtk::LdFlagsFile()` in their `configure` / `configure.win` scripts to obtain
the correct compiler and linker flags for the detected or downloaded VTK
installation.
