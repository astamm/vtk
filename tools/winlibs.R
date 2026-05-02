## tools/winlibs.R
## Called by configure.win when no system VTK is found.
## Downloads pre-built VTK libraries and headers from:
##   https://github.com/astamm/rvtk/releases
## and writes inst/vtk.conf so that rvtk::CppFlags() / rvtk::LdFlags() work.
##
## VTK_LINK_TYPE environment variable (default "static"):
##   "static"  -- download .a static libraries (vtk-X.Y.Z-static-posix-x64.zip)
##   "shared"  -- download .dll.a import libs + DLLs (vtk-X.Y.Z-shared-posix-x64.zip)
##
## For the shared build the VTK DLLs are copied to inst/libs/x64/ so that R
## adds the directory to the Windows DLL search path when rvtk is loaded.

vtk_version <- "9.5.2"

link_type <- Sys.getenv("VTK_LINK_TYPE", unset = "static")
if (!link_type %in% c("static", "shared")) {
  warning("VTK_LINK_TYPE='", link_type, "' is not recognised; using 'static'.")
  link_type <- "static"
}

## The toolchain prefix is the same for both variants; the zip name differs.
toolchain <- if (link_type == "shared") "shared-posix" else "static-posix"
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

## \u2500\u2500 Download and extract \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
message(
  "Downloading VTK ",
  vtk_version,
  " (",
  toolchain,
  "/",
  arch,
  ", ",
  link_type,
  " libs)"
)
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
      "To choose between static and shared DLL builds set VTK_LINK_TYPE to\n",
      "'static' (default) or 'shared' before installing.\n",
      "Pre-built binaries are available at\n",
      "<https://github.com/astamm/rvtk/releases>.\n",
      "Original error: ",
      conditionMessage(e)
    )
  }
)

tmp_extract <- tempfile("rvtk_vtk_")
dir.create(tmp_extract, recursive = TRUE, showWarnings = FALSE)
unzip(tmp, exdir = tmp_extract)
unlink(tmp)

dir.create(
  file.path(inst_dir, "windows"),
  recursive = TRUE,
  showWarnings = FALSE
)
extracted <- list.files(tmp_extract, full.names = TRUE)
for (item in extracted) {
  file.copy(
    item,
    file.path(inst_dir, "windows"),
    recursive = TRUE,
    overwrite = TRUE
  )
}
unlink(tmp_extract, recursive = TRUE)

## \u2500\u2500 Locate include and lib dirs inside the extracted archive \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
include_root <- file.path(dest_dir, "include")
lib_root <- file.path(dest_dir, "lib")

versioned_dirs <- list.dirs(include_root, recursive = FALSE)
versioned_dirs <- grep(
  "vtk-[0-9]",
  basename(versioned_dirs),
  value = TRUE
)

if (length(versioned_dirs) > 0) {
  suffix_dir <- versioned_dirs[length(versioned_dirs)]
  include_dir <- file.path(include_root, suffix_dir)
  lib_suffix <- sub("^vtk", "", suffix_dir)
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

## \u2500\u2500 For shared builds: copy DLLs into inst/libs/x64/ \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
## The .onLoad hook in R/vtk.R prepends inst/vtk-dlls/ to PATH via
## Sys.setenv() when rvtk is loaded.  This ensures downstream packages
## which declare 'Imports: rvtk' can load VTK-linked code without any
## manual PATH manipulation.  (AddDllDirectory() is not exposed at the R
## level; PATH mutation is the standard pure-R alternative.)
if (link_type == "shared") {
  bin_dir <- file.path(dest_dir, "bin")
  if (!dir.exists(bin_dir)) {
    stop(
      "Shared build archive is missing the 'bin/' directory with VTK DLLs.\n",
      "  Expected: ",
      bin_dir
    )
  }
  dll_dest <- file.path(inst_dir, "libs", "x64")
  dir.create(dll_dest, recursive = TRUE, showWarnings = FALSE)
  dlls <- list.files(bin_dir, pattern = "\\.dll$", full.names = TRUE)
  n_copied <- 0L
  for (dll in dlls) {
    file.copy(dll, dll_dest, overwrite = TRUE)
    n_copied <- n_copied + 1L
  }
  message("Copied ", n_copied, " VTK DLL(s) to ", dll_dest)
}

## \u2500\u2500 Write inst/vtk.conf \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
## Store version, suffix, subdir, and link type.
## CppFlags() / LdFlags() resolve actual installed paths at runtime via
## system.file(), so only symbolic identifiers go here.
dir.create(inst_dir, showWarnings = FALSE)
conf_path <- file.path(inst_dir, "vtk.conf")
writeLines(
  c(
    sprintf("VTK_VERSION=%s", vtk_version),
    sprintf("VTK_SUFFIX=%s", lib_suffix),
    sprintf("VTK_SUBDIR=%s", basename(dest_dir)),
    sprintf("VTK_LINK=%s", link_type)
  ),
  con = conf_path
)

message("Written: ", conf_path)
message("  VTK_VERSION=", vtk_version)
message("  VTK_SUFFIX=", lib_suffix)
message("  VTK_SUBDIR=", basename(dest_dir))
message("  VTK_LINK=", link_type)

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

## Extract to a temporary directory first, then copy to inst/windows/.
## This avoids writing stale intermediate files to the package source tree.
tmp_extract <- tempfile("rvtk_vtk_")
dir.create(tmp_extract, recursive = TRUE, showWarnings = FALSE)
unzip(tmp, exdir = tmp_extract)
unlink(tmp)

## Copy extracted content into inst/windows/, creating it if needed.
dir.create(
  file.path(inst_dir, "windows"),
  recursive = TRUE,
  showWarnings = FALSE
)
extracted <- list.files(tmp_extract, full.names = TRUE)
for (item in extracted) {
  file.copy(
    item,
    file.path(inst_dir, "windows"),
    recursive = TRUE,
    overwrite = TRUE
  )
}
unlink(tmp_extract, recursive = TRUE)

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
  ## Windows system library required by VTK (static.posix build):
  ## gdi32 - GDI functions used by vtkWin32OutputWindow.
  ## POSIX threading / libc symbols are resolved automatically by the
  ## x86_64-w64-mingw32.static.posix toolchain's default link libraries.
  "-lgdi32"
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
