# tools/vtk-detect.sh -- shared VTK detection helpers.
# Source this file (. tools/vtk-detect.sh) from configure / configure.win.
#
# Caller must set before sourcing:
#   VTK_MIN_SUFFIX        e.g. "9.1"

## vtk_detect_from_prefix PREFIX
## On success sets vtk_include_dir and vtk_version_suffix and returns 0.
vtk_detect_from_prefix() {
    _prefix="$1"
    _min="${VTK_MIN_SUFFIX}"

    ## Versioned include directory (vtk-X.Y)
    _vdir="$(find "${_prefix}/include" -maxdepth 1 -name "vtk-*" -type d 2>/dev/null \
        | sort -V | tail -1)"
    if test -n "${_vdir}"; then
        _sfx="$(basename "${_vdir}" | sed 's/^vtk-//')"
        if printf '%s\n%s\n' "${_min}" "${_sfx}" | sort -V | head -1 \
                | grep -qx "${_min}"; then
            vtk_version_suffix="${_sfx}"
            vtk_include_dir="${_vdir}"
            return 0
        fi
        return 1
    fi

    ## Unversioned include directory (vtk/)
    if test -d "${_prefix}/include/vtk"; then
        _hdr="${_prefix}/include/vtk/vtkVersionQuick.h"
        if test -f "${_hdr}"; then
            _major="$(grep '#define VTK_MAJOR_VERSION' "${_hdr}" | awk '{print $3}')"
            _minor="$(grep '#define VTK_MINOR_VERSION' "${_hdr}" | awk '{print $3}')"
            if test -n "${_major}" && test -n "${_minor}"; then
                _det="${_major}.${_minor}"
                if printf '%s\n%s\n' "${_min}" "${_det}" | sort -V | head -1 \
                        | grep -qx "${_min}"; then
                    vtk_version_suffix=""
                    vtk_include_dir="${_prefix}/include/vtk"
                    return 0
                fi
                return 1
            fi
        fi
        echo "WARNING: Could not read VTK version from ${_hdr}; proceeding." >&2
        vtk_version_suffix=""
        vtk_include_dir="${_prefix}/include/vtk"
        return 0
    fi

    return 1
}

## Initialise shared state variables.
vtk_found="no"
vtk_version_suffix=""
vtk_include_dir=""
vtk_lib_dir=""
vtk_cppflags=""
vtk_libs=""
vtk_version=""
