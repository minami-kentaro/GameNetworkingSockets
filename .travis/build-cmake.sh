#!/bin/bash
#
# CMake build tests
#

set -e

cmake_configure() {
	BUILD_DIR="$1"
	shift
	mkdir -p "$BUILD_DIR"
	(cd "$BUILD_DIR"; cmake "$@" ..)
}

cmake_build() {
	BUILD_DIR="$1"
	shift
	cmake --build "$BUILD_DIR" -- -v "$@"
}

cleanup() {
	echo "Cleaning up CMake build directories" >&2
	rm -rf build-{a,ub,t}san build-cmake
}

trap cleanup EXIT
cleanup

CMAKE_ARGS=(
	-G Ninja
	-DLIGHT_TESTS:BOOL=ON
	-DWERROR=ON
)

BUILD_SANITIZERS=${BUILD_SANITIZERS:-0}
[[ $(uname -s) == MINGW* ]] && BUILD_SANITIZERS=0

# Noticed that Clang's tsan and asan don't behave well on non-x86_64 Travis
# builders, so let's just disable them on there.
[[ $(uname -m) != x86_64 ]] && [[ ${CXX} == *clang* ]] && BUILD_SANITIZERS=0

# Something's wrong with the GCC -fsanitize=address build on the s390x Travis
# builder, and it fails to link properly.
[[ $(uname -m) == s390x ]] && BUILD_SANITIZERS=0

# Foreign architecture docker containers don't support sanitizers.
[[ $(uname -m) != x86_64 ]] && grep -q -e AuthenticAMD -e GenuineIntel /proc/cpuinfo && BUILD_SANITIZERS=0

set -x

# Build some tests with sanitizers
if [[ $BUILD_SANITIZERS -ne 0 ]]; then
	cmake_configure build-asan ${CMAKE_ARGS[@]} -DSANITIZE_ADDRESS:BOOL=ON
	cmake_configure build-ubsan ${CMAKE_ARGS[@]} -DSANITIZE_UNDEFINED:BOOL=ON
	if [[ ${CXX} == *clang* ]]; then
		cmake_configure build-tsan ${CMAKE_ARGS[@]} -DSANITIZE_THREAD:BOOL=ON
	fi
fi

cmake_configure build-cmake ${CMAKE_ARGS[@]} -DCMAKE_BUILD_TYPE=RelWithDebInfo ..

# Build normal unsanitized binaries
cmake_build build-cmake

# Build specific extended tests for code correctness validation
if [[ $BUILD_SANITIZERS -ne 0 ]]; then
	cmake_build build-asan test_connection test_crypto
	cmake_build build-ubsan test_connection test_crypto
	if [[ -d build-tsan ]]; then
		cmake_build build-tsan test_connection test_crypto
	fi
fi

# Run basic tests
build-cmake/tests/test_crypto
build-cmake/tests/test_connection

# Run sanitized builds
if [[ $BUILD_SANITIZERS -ne 0 ]]; then
	for SANITIZER in asan ubsan tsan; do
		[[ -d build-${SANITIZER} ]] || continue
		build-${SANITIZER}/tests/test_crypto
		build-${SANITIZER}/tests/test_connection
	done
fi

set +x

exit 0
