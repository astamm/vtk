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
## For the shared build the VTK DLLs are copied to inst/vtk-dlls/ so that
## R's .onLoad hook (R/zzz.R) can prepend that directory to PATH, making the
## DLLs visible to all subsequently loaded packages that link against VTK.

vtk_version <- "9.5.2"

link_type <- Sys.getenv("VTK_LINK_TYPE", unset = "static")
if (!link_type %in% c("static", "shared")) {
  warning("VTK_LINK_TYPE='", link_type, "' is not recognised; using 'static'.")
  link_type <- "static"
}

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

## Download and extract
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

## Extract to a temporary directory first, then copy to inst/windows/.
## This avoids writing stale intermediate files to the package source tree.
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

## Locate include and lib dirs inside the extracted archive
include_root <- file.path(dest_dir, "include")

versioned_dirs <- list.dirs(include_root, recursive = FALSE)
versioned_dirs <- grep(
  "vtk-[0-9]",
  basename(versioned_dirs),
  value = TRUE
)

if (length(versioned_dirs) > 0) {
  ## Pick the highest version if multiple exist.
  suffix_dir <- versioned_dirs[length(versioned_dirs)]
  include_dir <- file.path(include_root, suffix_dir)
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

## For shared builds: copy DLLs into inst/vtk-dlls/.
## R's .onLoad hook (R/zzz.R) prepends that directory to PATH via
## Sys.setenv() so that downstream packages which declare 'Imports: rvtk'
## can load VTK-linked code without any manual PATH manipulation.
if (link_type == "shared") {
  bin_dir <- file.path(dest_dir, "bin")
  if (!dir.exists(bin_dir)) {
    stop(
      "Shared build archive is missing the 'bin/' directory with VTK DLLs.\n",
      "  Expected: ",
      bin_dir
    )
  }
  dll_dest <- file.path(inst_dir, "vtk-dlls")
  dir.create(dll_dest, recursive = TRUE, showWarnings = FALSE)
  dlls <- list.files(bin_dir, pattern = "\\.dll$", full.names = TRUE)
  n_copied <- 0L
  for (dll in dlls) {
    file.copy(dll, dll_dest, overwrite = TRUE)
    n_copied <- n_copied + 1L
  }
  message("Copied ", n_copied, " VTK DLL(s) to ", dll_dest)
}

## Write inst/vtk.conf with symbolic identifiers only.
## CppFlags() / LdFlags() resolve the actual installed paths at runtime via
## system.file(), so only symbolic keys go here.
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
