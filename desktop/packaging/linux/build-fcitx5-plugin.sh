#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds fcitx5-qt's Qt 6 platform input context plugin against the same
# private Qt the desktop app is built with, plus its Fcitx5Qt6DBusAddons
# dependency.
#
# A distro's fcitx5-frontend-qt6 is built against the distro Qt. It cannot be
# loaded into a bundled Qt 6.12: Qt's private API it uses changed between Qt
# 6.4 and 6.12 (QWindowSystemInterface::handleExtendedKeyEvent lost a
# parameter), so the plugin fails with an undefined symbol and the app has no
# input method at all. Building fcitx5-qt against the bundled Qt avoids that.
#
# Usage: build-fcitx5-plugin.sh <qt-prefix> <staging-dir>
#
# Environment overrides:
#   NECTARLINK_FCITX5_QT_VERSION   fcitx5-qt tag (default: 5.1.16)
#   NECTARLINK_ECM_VERSION         extra-cmake-modules tag (default: 6.10.0)
#   NECTARLINK_FCITX5_QT_SOURCE    existing fcitx5-qt source tree (skips the download)
#   NECTARLINK_FCITX5_QT_CACHE     cache/work directory (default: ~/.cache/nectarlink/fcitx5-qt)
#
# Produces:
#   <staging-dir>/platforminputcontexts/libfcitx5platforminputcontextplugin.so
#   <staging-dir>/lib/libFcitx5Qt6DBusAddons.so{,.1,.5.1.16}

set -euo pipefail

QT_PREFIX="${1:?usage: build-fcitx5-plugin.sh <qt-prefix> <staging-dir>}"
OUT_DIR="${2:?usage: build-fcitx5-plugin.sh <qt-prefix> <staging-dir>}"

FCITX5_QT_VERSION="${NECTARLINK_FCITX5_QT_VERSION:-5.1.16}"
ECM_VERSION="${NECTARLINK_ECM_VERSION:-6.10.0}"
CACHE_DIR="${NECTARLINK_FCITX5_QT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/nectarlink/fcitx5-qt}"

FCITX5_QT_URL="https://github.com/fcitx/fcitx5-qt/archive/refs/tags/${FCITX5_QT_VERSION}.tar.gz"
FCITX5_QT_SHA256="94883b1f5501b9e8e994ce1790932750457d284dae992603cb40675c00eedea5"
ECM_URL="https://github.com/KDE/extra-cmake-modules/archive/refs/tags/v${ECM_VERSION}.tar.gz"
ECM_SHA256="96970136cf38c810f4ef90a33ad4ef9c8977956e1a6a02a179b7abf3a8967b34"

die() { echo "error: $*" >&2; exit 1; }
note() { echo "fcitx5-qt: $*" >&2; }

if ! find "${QT_PREFIX}/lib" -maxdepth 5 -name Qt6Config.cmake -print -quit 2>/dev/null | grep -q .; then
    die "no Qt 6 CMake package under ${QT_PREFIX} (is this the Qt prefix?)"
fi
command -v cmake >/dev/null 2>&1 || die "cmake is required to build the fcitx5 Qt6 plugin"
command -v curl >/dev/null 2>&1 || die "curl is required to download the fcitx5-qt sources"

if ! find /usr/lib /usr/lib64 /usr/local/lib -maxdepth 5 -path '*cmake/Fcitx5Utils/Fcitx5UtilsConfig.cmake' -print -quit 2>/dev/null | grep -q .; then
    die "Fcitx5Utils development files are missing (e.g. apt install libfcitx5utils-dev)"
fi

mkdir -p "${CACHE_DIR}/src" "${OUT_DIR}/platforminputcontexts" "${OUT_DIR}/lib"

hash="$(printf '%s' "${QT_PREFIX}" | sha256sum | cut -c1-12)"
BUILD_DIR="${CACHE_DIR}/build-${FCITX5_QT_VERSION}-${hash}"
GENERATOR=""
if command -v ninja >/dev/null 2>&1; then
    GENERATOR="-G Ninja"
fi

fetch() {
    local url="$1" dest="$2" sha="$3"
    if [[ -f "${dest}" ]]; then
        echo "${sha}  ${dest}" | sha256sum --check --status && return 0
        note "checksum mismatch for ${dest}; downloading again"
        rm -f "${dest}"
    fi
    note "downloading ${url}"
    curl -fsSL --retry 3 -o "${dest}.part" "${url}" || die "could not download ${url}"
    echo "${sha}  ${dest}.part" | sha256sum --check --status || die "checksum mismatch for ${url}"
    mv "${dest}.part" "${dest}"
}

# extra-cmake-modules is only needed to configure fcitx5-qt.
ECM_INSTALL="${CACHE_DIR}/ecm-${ECM_VERSION}"
if [[ ! -f "${ECM_INSTALL}/share/ECM/cmake/ECMConfig.cmake" ]]; then
    fetch "${ECM_URL}" "${CACHE_DIR}/src/ecm-${ECM_VERSION}.tar.gz" "${ECM_SHA256}"
    rm -rf "${CACHE_DIR}/src/ecm-${ECM_VERSION}"
    tar -xzf "${CACHE_DIR}/src/ecm-${ECM_VERSION}.tar.gz" -C "${CACHE_DIR}/src"
    ecm_log="${CACHE_DIR}/ecm-build.log"
    if ! {
        cmake -S "${CACHE_DIR}/src/extra-cmake-modules-${ECM_VERSION}" -B "${CACHE_DIR}/ecm-build-${ECM_VERSION}" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="${ECM_INSTALL}" \
            -DBUILD_TESTING=OFF &&
        cmake --install "${CACHE_DIR}/ecm-build-${ECM_VERSION}"
    } >"${ecm_log}" 2>&1; then
        echo "error: building extra-cmake-modules failed; see ${ecm_log}" >&2
        tail -40 "${ecm_log}" >&2 || true
        exit 1
    fi
fi

source_dir="${NECTARLINK_FCITX5_QT_SOURCE:-}"
if [[ -z "${source_dir}" ]]; then
    fetch "${FCITX5_QT_URL}" "${CACHE_DIR}/src/fcitx5-qt-${FCITX5_QT_VERSION}.tar.gz" "${FCITX5_QT_SHA256}"
    rm -rf "${CACHE_DIR}/src/fcitx5-qt-${FCITX5_QT_VERSION}"
    tar -xzf "${CACHE_DIR}/src/fcitx5-qt-${FCITX5_QT_VERSION}.tar.gz" -C "${CACHE_DIR}/src"
    source_dir="${CACHE_DIR}/src/fcitx5-qt-${FCITX5_QT_VERSION}"
fi
[[ -f "${source_dir}/CMakeLists.txt" ]] || die "${source_dir} is not an fcitx5-qt source tree"

wayland=OFF
if [[ -d "${QT_PREFIX}/lib/cmake/Qt6WaylandGlobalPrivate" && -d "${QT_PREFIX}/lib/cmake/Qt6WaylandClientPrivate" ]]; then
    wayland=ON
fi

note "building fcitx5-qt ${FCITX5_QT_VERSION} against ${QT_PREFIX}"
fcitx_log="${CACHE_DIR}/fcitx5-qt-build.log"
if ! {
    cmake -S "${source_dir}" -B "${BUILD_DIR}" ${GENERATOR} \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${CACHE_DIR}/install-${FCITX5_QT_VERSION}" \
        -DCMAKE_PREFIX_PATH="${ECM_INSTALL};${QT_PREFIX}" \
        -DCMAKE_SKIP_RPATH=ON \
        -DENABLE_QT4=OFF \
        -DENABLE_QT5=OFF \
        -DENABLE_QT6=ON \
        -DENABLE_X11=ON \
        -DENABLE_QT6_WAYLAND_WORKAROUND="${wayland}" &&
    cmake --build "${BUILD_DIR}" --target fcitx5platforminputcontextplugin-qt6 Fcitx5Qt6DBusAddons \
        -j "$(nproc)"
} >"${fcitx_log}" 2>&1; then
    echo "error: building fcitx5-qt failed; see ${fcitx_log}" >&2
    tail -40 "${fcitx_log}" >&2 || true
    exit 1
fi

plugin="${BUILD_DIR}/qt6/platforminputcontext/libfcitx5platforminputcontextplugin.so"
addons_dir="${BUILD_DIR}/qt6/dbusaddons"
[[ -f "${plugin}" ]] || die "the fcitx5 input context plugin was not built"
compgen -G "${addons_dir}/libFcitx5Qt6DBusAddons.so*" >/dev/null || die "Fcitx5Qt6DBusAddons was not built"

install -m 0755 "${plugin}" "${OUT_DIR}/platforminputcontexts/libfcitx5platforminputcontextplugin.so"
cp -a "${addons_dir}"/libFcitx5Qt6DBusAddons.so* "${OUT_DIR}/lib/"
note "done: ${OUT_DIR}"