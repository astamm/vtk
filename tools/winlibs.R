## tools/winlibs.R
## Called by configure.win.
## Downloads pre-built VTK static libraries and headers from:
##   https://github.com/astamm/rvtk/releases
## and writes inst/vtk.conf so that rvtk::CppFlags() / rvtk::LdFlags() work.

vtk_version <- "9.5.2"

## The Windows zip is always built with the x86_64-w64-mingw32.static.posix
## toolchain — the same one used by R CMD INSTALL on Rtools45.  There is no
## per-MSYSTEM branching: one toolchain, one binary.
toolchain <- "static-posix"

## Only x86_64 is supported for now; arm64 support can be added later.
arch <- "x64"

zip_name <- sprintf("vtk-%s-%s-%s.zip", vtk_version, toolchain, arch)
url <- sprintf(
  "https://github.com/astamm/rvtk/releases/download/v%s/%s",
  vtk_version,
  zip_name
)

dest_dir <- file.path(
  "inst",
  "windows",
  sprintf("vtk-%s-%s-%s", vtk_version, toolchain, arch)
)
inst_dir <- "inst"

## ── Download and extract ─────────────────────────────────────────────────────
if (!dir.exists(dest_dir)) {
  message("Downloading VTK ", vtk_version, " (", toolchain, "/", arch, ")")
  message("  URL: ", url)

  tmp <- tempfile(fileext = ".zip")
  tryCatch(
    download.file(url, destfile = tmp, quiet = FALSE, mode = "wb"),
    error = function(e) {
      stop(
        "Failed to download VTK libraries.\n",
        "  URL: ",
        url,
        "\n",
        "If you have a local VTK installation, set the VTK_DIR environment\n",
        "variable to its prefix and re-install.\n",
        "Pre-built binaries are available at\n",
        "<https://github.com/astamm/rvtk/releases>.\n",
        "Original error: ",
        conditionMessage(e)
      )
    }
  )

  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  unzip(tmp, exdir = file.path("inst", "windows"))
  unlink(tmp)
} else {
  message("Using cached VTK at: ", dest_dir)
}

## ── Locate include and lib dirs inside the extracted archive ─────────────────
include_root <- file.path(dest_dir, "include")
lib_root <- file.path(dest_dir, "lib")

## Support both versioned (vtk-X.Y) and unversioned (vtk) sub-directories.
versioned_dirs <- list.dirs(include_root, recursive = FALSE)
versioned_dirs <- grep(
  "vtk-[0-9]",
  basename(versioned_dirs),
  value = TRUE
)

if (length(versioned_dirs) > 0) {
  ## Pick the highest version if multiple exist.
  suffix_dir <- versioned_dirs[length(versioned_dirs)] # bare name e.g. vtk-9.5
  include_dir <- file.path(include_root, suffix_dir)
  ## lib names are e.g. libvtkIOLegacy-9.5.a → strip the leading "vtk"
  lib_suffix <- sub("^vtk", "", suffix_dir) # e.g. -9.5
} else if (dir.exists(file.path(include_root, "vtk"))) {
  include_dir <- file.path(include_root, "vtk")
  lib_suffix <- ""
} else {
  stop(
    "Cannot locate VTK include directory in the downloaded archive at:\n  ",
    dest_dir,
    "\nExpected either 'include/vtk-X.Y/' or 'include/vtk/'."
  )
}

include_dir <- normalizePath(include_dir, winslash = "/")
lib_dir <- normalizePath(lib_root, winslash = "/")

## ── Build compiler / linker flag strings ─────────────────────────────────────
vtk_cppflags <- sprintf('-I"%s"', include_dir)

## Discover every .a in the lib directory and wrap in a linker group so that
## the linker resolves circular dependencies regardless of ordering.
all_libs <- list.files(lib_dir, pattern = "\\.a$", full.names = FALSE)
lib_flags <- paste(
  sprintf("-l%s", sub("\\.a$", "", sub("^lib", "", all_libs))),
  collapse = " "
)
vtk_libs <- paste(
  sprintf('-L"%s"', lib_dir),
  "-Wl,--start-group",
  lib_flags,
  "-Wl,--end-group",
  ## Windows system libraries required by VTK modules:
  ## gdi32      - GDI functions (vtkWin32OutputWindow)
  ## winpthread - nanosleep64 / POSIX threads (vtkloguru)
  ## mingwex    - ftime64 and other POSIX wrappers (vtkCommonSystem)
  ## ucrtbase   - __imp_fseeko64, __imp_ftello64 (vtkpugixml)
  "-lgdi32 -lwinpthread -lmingwex -lucrtbase"
)

## ── Write inst/vtk.conf ───────────────────────────────────────────────────────
## Store only the version and suffix — CppFlags() / LdFlags() will compute
## the actual installed paths at runtime via system.file().
dir.create(inst_dir, showWarnings = FALSE)
conf_path <- file.path(inst_dir, "vtk.conf")
writeLines(
  c(
    sprintf("VTK_VERSION=%s", vtk_version),
    sprintf("VTK_SUFFIX=%s", lib_suffix),
    sprintf("VTK_SUBDIR=%s", basename(dest_dir))
  ),
  con = conf_path
)

message("Written: ", conf_path)
message("  VTK_VERSION=", vtk_version)
message("  VTK_SUFFIX=", lib_suffix)
message("  VTK_SUBDIR=", basename(dest_dir))
