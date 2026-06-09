#!/bin/bash
#
# build_highs.sh — Build a static HiGHS library (libhighs.a) from source.
#
# Called by ./configure before build_uno.sh. Produces src/highslib/ with
# include/highs/ and lib/libhighs.a, which Uno's CMake picks up via
# -DHIGHS=.../libhighs.a to compile its HiGHS QP/LP subproblem solver.
#
# Adapted from inst/build_highs.sh in the highs R package, but builds
# OUT OF SOURCE (cmake -S <src> -B <build>) so the HiGHS source tree
# (a submodule) is never dirtied.

#
# Detect tools (no `set -e`: the which-fallback chain assigns failing command
# substitutions inside if-branches, which set -e treats as fatal).
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

# Use R's toolchain throughout: R's compiler AND R's flags, so the static
# archive is built exactly as R would build package code (ABI + flags match).
# CMake reads CFLAGS/CXXFLAGS/LDFLAGS from the environment at first configure.
# R's CPPFLAGS (preprocessor defs) is folded into C/CXX flags since CMake has
# no CPPFLAGS concept. No R/Rcpp include dirs are added — HiGHS stays pristine.
CFLAGS=`"${R_HOME}/bin/R" CMD config CFLAGS`
CXXFLAGS=`"${R_HOME}/bin/R" CMD config CXXFLAGS`
CPPFLAGS=`"${R_HOME}/bin/R" CMD config CPPFLAGS`
export CC=`"${R_HOME}/bin/R" CMD config CC`
export CXX=`"${R_HOME}/bin/R" CMD config CXX17`
export CFLAGS="${CFLAGS} ${CPPFLAGS}"
export CXXFLAGS="${CXXFLAGS} ${CPPFLAGS}"
export LDFLAGS=`"${R_HOME}/bin/R" CMD config LDFLAGS`

R_UNO_PKG_HOME=`pwd`
HIGHS_SRC_DIR=${R_UNO_PKG_HOME}/inst/HiGHS
HIGHS_BUILD_DIR=${R_UNO_PKG_HOME}/highs_build
HIGHS_INSTALL_DIR=${R_UNO_PKG_HOME}/src/highslib

# R-package console-I/O redirection.  HConfig.h (#ifdef HIGHS_R_PRINT) pulls in
# highs/io/r_io.h, which routes stdout/printf/std::cout to R so the libc stdout /
# printf / std::cout symbols never appear in libhighs.a (needed for R CMD check
# "checking compiled code").  Only standard, universally-supported preprocessor
# flags are used: -DHIGHS_R_PRINT to enable the hook and -I<R>/include so
# r_io.h can find <R_ext/Print.h>.  Applied to BOTH C and C++ (the bundled
# cupdlp_*.c files also emit printf symbols), which is why r_io.h is C-safe.
# R header include path: query R itself via R.home("include") (== R_INCLUDE_DIR),
# which is always present and correct on every platform (Debian/Ubuntu and
# r-universe put the headers in e.g. /usr/share/R/include, NOT ${R_HOME}/include).
# Do NOT use `R CMD config --cppflags`: that is the "compile against the R library"
# (embedding) query and returns NOTHING -- "R was not built as a library" -- when R
# is built without --enable-R-shlib, as on CRAN's fedora-gcc/clang and musl machines,
# which left this compile with no R include path -> <R_ext/Error.h> not found.
R_INCLUDE_DIR=`"${R_HOME}/bin/Rscript" -e 'cat(R.home("include"))'`
R_HDR_FLAGS="-I${R_INCLUDE_DIR}"
HIGHS_RIO_FLAGS="-DHIGHS_R_PRINT ${R_HDR_FLAGS}"
export CFLAGS="${CFLAGS} ${HIGHS_RIO_FLAGS}"
export CXXFLAGS="${CXXFLAGS} ${HIGHS_RIO_FLAGS}"

if test ! -f "${HIGHS_SRC_DIR}/CMakeLists.txt"; then
    echo "HiGHS source not found at '${HIGHS_SRC_DIR}'."
    echo "Initialize the submodule: git submodule update --init inst/HiGHS"
    exit 1
fi

echo ""
echo "CMAKE VERSION:    '`${CMAKE_EXE} --version | head -n 1`'"
echo "CC:               '${CC}'"
echo "CXX:              '${CXX}'"
echo "HIGHS_SRC_DIR:    '${HIGHS_SRC_DIR}'"
echo "HIGHS_INSTALL_DIR:'${HIGHS_INSTALL_DIR}'"
echo ""

#
# Detect ccache
#
CCACHE_OPTS=""
CCACHE_EXE=`which ccache 2>/dev/null`
if test -n "${CCACHE_EXE}"; then
    CCACHE_OPTS="-DCMAKE_C_COMPILER_LAUNCHER=${CCACHE_EXE} -DCMAKE_CXX_COMPILER_LAUNCHER=${CCACHE_EXE}"
    echo "Found ccache: ${CCACHE_EXE}"
fi

mkdir -p "${HIGHS_INSTALL_DIR}"

CMAKE_OPTS="
    -DCMAKE_INSTALL_PREFIX=${HIGHS_INSTALL_DIR}
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_POSITION_INDEPENDENT_CODE:bool=ON
    -DBUILD_SHARED_LIBS:bool=OFF
    -DBUILD_TESTING:bool=OFF
    -DZLIB:bool=OFF
    -DBUILD_EXAMPLES:bool=OFF
    -DBUILD_CXX_EXE:bool=OFF
    -DFAST_BUILD:bool=ON
    -DCMAKE_VERBOSE_MAKEFILE:bool=ON
    -DCUPDLP_GPU:bool=OFF
    -DUSE_DOTNET_STD_21:bool=OFF
    -DHIGHS_R_NO_DOC_INSTALL:bool=ON
    ${CCACHE_OPTS}
"

if test "$(uname -s)" = "Darwin"; then
    CMAKE_PLATFORM_OPTS="-DCMAKE_HOST_APPLE:bool=ON"
else
    CMAKE_PLATFORM_OPTS="-G \"Unix Makefiles\""
fi

# NOTE on doc files / CITATION.cff: HiGHS's CMakeLists.txt has an install(FILES
# README.md LICENSE.txt AUTHORS CITATION.cff ... DESTINATION ${CMAKE_INSTALL_DOCDIR})
# rule.  We pass -DHIGHS_R_NO_DOC_INSTALL=ON (a guarded fork addition) above to
# skip it entirely: those docs are irrelevant to the consumed libhighs.a, the
# stripped-from-tarball CITATION.cff would otherwise abort the install with
# "file INSTALL cannot find ... CITATION.cff", and an installed
# share/doc/HIGHS/CITATION.cff would trip R CMD check's "CITATION file in a
# non-standard place" NOTE.  Skipping the doc install avoids both with no
# placeholder files and no pollution of the unpacked source tree.

eval ${CMAKE_EXE} -S "${HIGHS_SRC_DIR}" -B "${HIGHS_BUILD_DIR}" ${CMAKE_OPTS} ${CMAKE_PLATFORM_OPTS} || exit 1
# Default to 2 parallel jobs: CRAN policy asks installs to use at most 2 cores
# (a higher default tripped the "CPU time N times elapsed" install NOTE).
# Developers/CI can raise it via UNO_BUILD_JOBS.
${CMAKE_EXE} --build "${HIGHS_BUILD_DIR}" --target install -j"${UNO_BUILD_JOBS:-2}" || exit 1

cd "${R_UNO_PKG_HOME}"

# HiGHS may install into lib/ or lib64/; normalize to lib/.
if test ! -f "${HIGHS_INSTALL_DIR}/lib/libhighs.a" && test -f "${HIGHS_INSTALL_DIR}/lib64/libhighs.a"; then
    mkdir -p "${HIGHS_INSTALL_DIR}/lib"
    cp "${HIGHS_INSTALL_DIR}/lib64/libhighs.a" "${HIGHS_INSTALL_DIR}/lib/"
fi

if test ! -f "${HIGHS_INSTALL_DIR}/lib/libhighs.a"; then
    echo "HiGHS static library (libhighs.a) was not produced!"
    exit 1
fi

echo ">>> HiGHS installed to ${HIGHS_INSTALL_DIR}"
