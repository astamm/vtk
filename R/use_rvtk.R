#' Set up a downstream package to use rvtk
#'
#' @description
#' A [usethis](https://usethis.r-lib.org/)-style helper that configures a
#' downstream R package to link against VTK via **rvtk**. It performs the
#' following steps:
#'
#' * Adds `rvtk` to the `Imports` field of `DESCRIPTION`.
#' * Writes `src/Makevars` that queries compiler and linker flags at install
#'   time by calling `tools/configure.R`.
#' * Writes `src/Makevars.win` with the Windows-specific `$(shell ...)` syntax
#'   that does the same.
#' * Writes `tools/configure.R` that calls [CppFlags()] and [LdFlagsFile()]
#'   with the requested VTK modules.
#' * Adds `src/vtk_libs.rsp` to `.gitignore` (it is generated at install time
#'   and must not be committed).
#' * Creates `R/rvtk_imports.R` with a minimal `@importFrom rvtk` roxygen tag
#'   so that `R CMD check` does not complain about **rvtk** being listed in
#'   `Imports` without any function import in the R code.
#'
#' After running `use_rvtk()` the downstream package is fully configured: VTK
#' compiler and linker flags are resolved automatically at `R CMD INSTALL` time
#' on all platforms without any shell `configure` / `configure.win` scripts.
#'
#' @param modules A character vector of VTK module names to link against.
#'   These are passed to [LdFlagsFile()] in the generated `tools/configure.R`,
#'   restricting linking to only the modules the downstream package needs.
#'   Defaults to a standard set covering common I/O and core modules
#'   (the same set used by the reference implementation in
#'   \url{https://github.com/astamm/riot}).
#' @param path Path to the root of the downstream package. Defaults to the
#'   current working directory.
#'
#' @return Invisibly, the normalised path to the package root. Called
#'   primarily for its side effects.
#'
#' @seealso [CppFlags()], [LdFlagsFile()]
#' @export
use_rvtk <- function(
  modules = c(
    "vtkIOLegacy",
    "vtkIOXML",
    "vtkIOXMLParser",
    "vtkIOCore",
    "vtkCommonCore",
    "vtkCommonDataModel",
    "vtkCommonExecutionModel",
    "vtkCommonMath",
    "vtkCommonMisc",
    "vtkCommonSystem",
    "vtkCommonTransforms",
    "vtksys"
  ),
  path = "."
) {
  path <- normalizePath(path, mustWork = TRUE)

  ## 1. Add rvtk to Imports in DESCRIPTION ------------------------------------
  rvtk_use_package(path)

  ## 2. src/Makevars ----------------------------------------------------------
  rvtk_write_file(
    path = file.path(path, "src", "Makevars"),
    content = paste0(
      'PKG_CPPFLAGS = `"$(R_HOME)/bin/Rscript" ../tools/configure.R --cppflags`\n',
      'PKG_LIBS = `"$(R_HOME)/bin/Rscript" ../tools/configure.R --libs`\n'
    ),
    root = path
  )

  ## 3. src/Makevars.win ------------------------------------------------------
  rvtk_write_file(
    path = file.path(path, "src", "Makevars.win"),
    content = paste0(
      'PKG_CPPFLAGS = $(shell "$(R_HOME)/bin$(R_ARCH_BIN)/Rscript" ../tools/configure.R --cppflags)\n',
      'PKG_LIBS = $(shell "$(R_HOME)/bin$(R_ARCH_BIN)/Rscript" ../tools/configure.R --libs)\n'
    ),
    root = path
  )

  ## 4. tools/configure.R -----------------------------------------------------
  modules_lines <- paste0('  "', modules, '"', collapse = ",\n")
  rvtk_write_file(
    path = file.path(path, "tools", "configure.R"),
    content = paste0(
      'args <- commandArgs(trailingOnly = TRUE)\n',
      'flag <- if (length(args)) args[1L] else "--cppflags"\n',
      '\n',
      'vtk_modules <- c(\n',
      modules_lines,
      '\n',
      ')\n',
      '\n',
      'if (flag == "--cppflags") {\n',
      '  rvtk::CppFlags()\n',
      '} else if (flag == "--libs") {\n',
      '  rvtk::LdFlagsFile(path = "vtk_libs.rsp", modules = vtk_modules)\n',
      '}\n'
    ),
    root = path
  )

  ## 5. .gitignore: keep generated response file out of version control -------
  rvtk_use_git_ignore("src/vtk_libs.rsp", root = path)

  ## 6. R/rvtk_imports.R: minimal importFrom to satisfy R CMD check -----------
  rvtk_write_file(
    path = file.path(path, "R", "rvtk_imports.R"),
    content = "#' @importFrom rvtk CppFlags LdFlagsFile\nNULL\n",
    root = path
  )

  cli::cli_alert_success(
    "Package {.pkg {basename(path)}} is now configured to link against VTK via {.pkg rvtk}."
  )
  invisible(path)
}

# Internal helpers -------------------------------------------------------------

## Add "rvtk" to the Imports field of DESCRIPTION (pure base R, no extra deps).
rvtk_use_package <- function(root) {
  desc_path <- file.path(root, "DESCRIPTION")
  if (!file.exists(desc_path)) {
    cli::cli_abort("No {.file DESCRIPTION} found in {.path {root}}.")
  }

  lines <- readLines(desc_path, warn = FALSE)

  imports_idx <- grep("^Imports:", lines)

  if (length(imports_idx) == 0L) {
    ## No Imports field yet — insert one.
    ## Find where Description ends (next unindented line or EOF).
    desc_start <- grep("^Description:", lines)
    if (length(desc_start) == 0L) {
      insert_before <- grep("^License:", lines)
      insert_before <- if (length(insert_before)) {
        insert_before[1L]
      } else {
        length(lines) + 1L
      }
    } else {
      i <- desc_start[1L] + 1L
      while (i <= length(lines) && grepl("^\\s", lines[i])) {
        i <- i + 1L
      }
      insert_before <- i
    }
    lines <- append(lines, "Imports: rvtk", after = insert_before - 1L)
    writeLines(lines, desc_path)
    cli::cli_alert_success(
      "Added {.pkg rvtk} to {.field Imports} in {.file DESCRIPTION}."
    )
    return(invisible(NULL))
  }

  ## Imports exists — find full span (field line + indented continuation lines).
  i <- imports_idx[1L]
  span_end <- i
  j <- i + 1L
  while (j <= length(lines) && grepl("^\\s", lines[j])) {
    span_end <- j
    j <- j + 1L
  }

  imports_block <- paste(lines[i:span_end], collapse = "\n")
  if (grepl("\\brvtk\\b", imports_block)) {
    cli::cli_alert_info(
      "{.pkg rvtk} is already in {.field Imports} — skipping."
    )
    return(invisible(NULL))
  }

  ## Append to existing Imports block: add trailing comma to the last entry,
  ## then insert an indented "rvtk" line.
  lines[span_end] <- paste0(trimws(lines[span_end], which = "right"), ",")
  lines <- append(lines, "    rvtk", after = span_end)
  writeLines(lines, desc_path)
  cli::cli_alert_success(
    "Added {.pkg rvtk} to {.field Imports} in {.file DESCRIPTION}."
  )
}

## Write a file, creating parent directories if needed.
## Asks before overwriting in interactive sessions; skips silently otherwise.
rvtk_write_file <- function(path, content, root = getwd()) {
  dir <- dirname(path)
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
  }

  rel <- rvtk_rel_path(path, root)

  if (file.exists(path)) {
    if (interactive()) {
      answer <- readline(
        cli::col_yellow(sprintf("'%s' already exists. Overwrite? [y/N] ", rel))
      )
      if (!tolower(trimws(answer)) %in% c("y", "yes")) {
        cli::cli_alert_warning("Skipping {.file {rel}} — not overwritten.")
        return(invisible(path))
      }
    } else {
      cli::cli_alert_warning("Skipping {.file {rel}} — already exists.")
      return(invisible(path))
    }
  }

  writeLines(content, con = path)
  cli::cli_alert_success("Writing {.file {rel}}.")
  invisible(path)
}

## Add a pattern to .gitignore if not already present.
rvtk_use_git_ignore <- function(pattern, root = getwd()) {
  gi_path <- file.path(root, ".gitignore")
  existing <- if (file.exists(gi_path)) {
    readLines(gi_path, warn = FALSE)
  } else {
    character(0)
  }

  if (pattern %in% trimws(existing)) {
    cli::cli_alert_info(
      "{.val {pattern}} already in {.file .gitignore} — skipping."
    )
    return(invisible(NULL))
  }

  cat(pattern, "\n", file = gi_path, append = TRUE, sep = "")
  cli::cli_alert_success("Adding {.val {pattern}} to {.file .gitignore}.")
}

## Return path relative to root, or the original path if outside root.
rvtk_rel_path <- function(path, root = getwd()) {
  prefix <- paste0(normalizePath(root, mustWork = FALSE), .Platform$file.sep)
  if (startsWith(path, prefix)) substring(path, nchar(prefix) + 1L) else path
}
