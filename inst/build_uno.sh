#!/bin/bash
#
# build_uno.sh — Build the Uno static library (libuno.a) from source via CMake.
#
# Called by ./configure during R CMD INSTALL. Produces src/unolib/ with
# include/ (the C API headers under include/uno/) and lib/libuno.a.
#
# Modeled on inst/build_highs.sh (highs R package) and inst/build_scip.sh
# (scip R package). The Uno C++ source is vendored as a git submodule at
# src/uno; HiGHS at src/HiGHS.
#
# Milestone A: builds uno_static WITHOUT any subproblem solver (no HiGHS),
# enough to validate the packaging chain and the uno_version() smoke binding.
# HiGHS wiring (-DHIGHS=...) is layered on in a later milestone.
#
# NOTE: do not use `set -e` here. The `which cmake4 || which cmake` fallback
# pattern assigns a failing command substitution inside an if-branch, which
# `set -e` treats as a fatal error. Critical steps below use explicit `|| exit 1`.

#
# Detect tools
#
if test -z "${MAKE}"; then MAKE=`which make 2>/dev/null`; fi
if test -z "${MAKE}"; then MAKE=`which /Applications/Xcode.app/Contents/Developer/usr/bin/make 2>/dev/null`; fi

if test -z "${CMAKE_EXE}"; then CMAKE_EXE=`which cmake4 2>/dev/null`; fi
if test -z "${CMAKE_EXE}"; then CMAKE_EXE=`which cmake3 2>/dev/null`; fi
if test -z "${CMAKE_EXE}"; then CMAKE_EXE=`which cmake 2>/dev/null`; fi
if test -z "${CMAKE_EXE}"; then CMAKE_EXE=`which /Applications/CMake.app/Contents/bin/cmake 2>/dev/null`; fi

if test -z "${CMAKE_EXE}"; then
    echo "Could not find 'cmake'!"
    exit 1
fi

: ${R_HOME=`R RHOME`}
if test -z "${R_HOME}"; then
    echo "'R_HOME' could not be found!"
    exit 1
fi

#
# Compiler settings from R (so the static archive's ABI matches the R session
# that will dlopen the package .so)
#
# Use R's toolchain throughout: R's compiler AND R's flags. CMake reads
# CFLAGS/CXXFLAGS/FFLAGS/LDFLAGS from the environment at first configure.
# R's CPPFLAGS is folded into C/CXX flags (CMake has no CPPFLAGS concept).
CFLAGS=`"${R_HOME}/bin/R" CMD config CFLAGS`
CXXFLAGS=`"${R_HOME}/bin/R" CMD config CXXFLAGS`
CPPFLAGS=`"${R_HOME}/bin/R" CMD config CPPFLAGS`
export CC=`"${R_HOME}/bin/R" CMD config CC`
export CXX=`"${R_HOME}/bin/R" CMD config CXX17`
export FC=`"${R_HOME}/bin/R" CMD config FC`
export FFLAGS=`"${R_HOME}/bin/R" CMD config FFLAGS`
export CFLAGS="${CFLAGS} ${CPPFLAGS}"
export CXXFLAGS="${CXXFLAGS} ${CPPFLAGS}"
export LDFLAGS=`"${R_HOME}/bin/R" CMD config LDFLAGS`

# R-package console-I/O redirection (mirror of build_highs.sh's HIGHS_R_PRINT).
# uno/tools/r_io.h (#ifdef UNO_R_PRINT, pulled in via Logger.hpp and the few
# files using std::cout) routes std::cout/std::cerr to R's console through a
# streambuf over Rprintf/REprintf, so the std::cout symbol never appears in
# libuno.a (needed for R CMD check "checking compiled code").  -I<R>/include
# lets r_io.h find <R_ext/Print.h>/<R_ext/Error.h>.  Uno's C++ uses no C printf
# or C `stdout` token, so no funopen/fopencookie FILE* redirect is needed and
# the fix is identically clean on macOS, Linux and Windows.
UNO_RIO_FLAGS="-DUNO_R_PRINT -I${R_HOME}/include"
export CFLAGS="${CFLAGS} ${UNO_RIO_FLAGS}"
export CXXFLAGS="${CXXFLAGS} ${UNO_RIO_FLAGS}"

R_UNO_PKG_HOME=`pwd`
UNO_SRC_DIR=${R_UNO_PKG_HOME}/src/uno              # Uno C++ source (git submodule)
UNO_BUILD_DIR=${R_UNO_PKG_HOME}/uno_build
UNO_INSTALL_DIR=${R_UNO_PKG_HOME}/src/unolib

echo ""
echo "CMAKE VERSION:  '`${CMAKE_EXE} --version | head -n 1`'"
echo "CC:             '${CC}'"
echo "CXX:            '${CXX}'"
echo "FC:             '${FC}'"
echo "UNO_SRC_DIR:    '${UNO_SRC_DIR}'"
echo "UNO_BUILD_DIR:  '${UNO_BUILD_DIR}'"
echo "UNO_INSTALL_DIR:'${UNO_INSTALL_DIR}'"
echo ""

if test ! -f "${UNO_SRC_DIR}/CMakeLists.txt"; then
    echo "Uno source not found at '${UNO_SRC_DIR}'."
    echo "Initialize the submodule: git submodule update --init src/uno"
    exit 1
fi

#
# Detect ccache for faster rebuilds (SCIP/HiGHS-style)
#
CCACHE_OPTS=""
CCACHE_EXE=`which ccache 2>/dev/null`
if test -n "${CCACHE_EXE}"; then
    CCACHE_OPTS="-DCMAKE_C_COMPILER_LAUNCHER=${CCACHE_EXE} -DCMAKE_CXX_COMPILER_LAUNCHER=${CCACHE_EXE}"
    echo "Found ccache: ${CCACHE_EXE}"
fi

#
# Optional HiGHS (Milestone B): if HIGHS_LIB is exported (path to libhighs.a),
# pre-seed the find_library(HIGHS) cache and add HAS_HIGHS to the build.
#
HIGHS_OPTS=""
if test -n "${HIGHS_LIB}"; then
    HIGHS_OPTS="-DHIGHS=${HIGHS_LIB}"
    echo "HiGHS: ${HIGHS_LIB}"
fi

#
# Optional MUMPS via rmumps: if MUMPS_R_INCLUDE_DIRS is exported (by ./configure,
# pointing at the rmumps package's include dir), enable Uno's MUMPS linear solver
# in HEADER-ONLY mode -- compile MUMPSSolver.cpp against rmumps' headers and link
# NO MUMPS/METIS/MPI/OpenMP library. dmumps_c is resolved at runtime via
# R_FindSymbol from rmumps (see interfaces/R/src/dmumps_shim.c).
#
MUMPS_OPTS=""
if test -n "${MUMPS_R_INCLUDE_DIRS}"; then
    MUMPS_OPTS="-DMUMPS_VIA_R:bool=ON -DMUMPS_R_INCLUDE_DIRS=${MUMPS_R_INCLUDE_DIRS}"
    echo "MUMPS (rmumps headers): ${MUMPS_R_INCLUDE_DIRS}"
fi

#
# Configure + build the static library
#
mkdir -p "${UNO_BUILD_DIR}"
cd "${UNO_BUILD_DIR}"

CMAKE_OPTS="
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_STATIC_LIBS:bool=ON
    -DBUILD_SHARED_LIBS:bool=OFF
    -DENABLE_TESTS:bool=OFF
    -DCMAKE_POSITION_INDEPENDENT_CODE:bool=ON
    -DCMAKE_INSTALL_PREFIX=${UNO_INSTALL_DIR}
    -DCMAKE_VERBOSE_MAKEFILE:bool=ON
    ${CCACHE_OPTS}
    ${HIGHS_OPTS}
    ${MUMPS_OPTS}
"

if test "$(uname -s)" = "Darwin"; then
    CMAKE_PLATFORM_OPTS="-DCMAKE_HOST_APPLE:bool=ON"
else
    # On Windows/Rtools CMake otherwise defaults to an "NMake"/VS generator and
    # fails; force the Rtools make. Harmless on Linux (already the default).
    CMAKE_PLATFORM_OPTS="-G \"Unix Makefiles\""
fi

eval ${CMAKE_EXE} "${UNO_SRC_DIR}" ${CMAKE_OPTS} ${CMAKE_PLATFORM_OPTS} || exit 1

${MAKE} -j"${UNO_BUILD_JOBS:-4}" install || exit 1

cd "${R_UNO_PKG_HOME}"

if test ! -f "${UNO_INSTALL_DIR}/lib/libuno.a"; then
    echo "Uno static library (libuno.a) was not produced!"
    exit 1
fi

echo ">>> Uno installed to ${UNO_INSTALL_DIR}"
