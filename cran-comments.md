## Resubmission

In this resubmission, we fixed URL issue pointing to https://github.com/astamm/riot
instead of https://github.com/tractoverse/riot.

The rest of CRAN check issues (linux-arm64 and musl/Alpine) have been addressed as
part of the original v0.2.0 submission.

## Submission (v0.2.0)

This submission adds aarch64 and musl/Alpine Linux support as well as a
convenience function `use_rvtk()` to simplify downstream package setup
and a number of bug fixes. See `NEWS.md` for details.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a re-submission.

## Notes

* The package downloads pre-built VTK 9.5.2 libraries at install time from
  <https://github.com/astamm/rvtk/releases/tag/v9.5.2> when no suitable system
  VTK installation is found.
* Pre-built binaries are now provided for Windows (Rtools45 static.posix x64,
  static and shared), macOS arm64, macOS x86_64, Linux x86_64 (glibc),
  Linux x86_64 (musl / Alpine), and Linux aarch64.
* No compiled code is included in the package itself (`NeedsCompilation: no`).
