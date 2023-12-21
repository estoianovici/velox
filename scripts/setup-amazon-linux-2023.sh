#!/bin/bash
# Copyright (c) Facebook, Inc. and its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Minimal setup for Amazon Linux 2
set -eufx -o pipefail
SCRIPTDIR=$(dirname "${BASH_SOURCE[0]}")
source $SCRIPTDIR/setup-helper-functions.sh

CPU_TARGET="${CPU_TARGET:-avx}"

COMPILER_FLAGS=$(get_cxx_flags "$CPU_TARGET")
export COMPILER_FLAGS

export CXXFLAGS=$COMPILER_FLAGS  # Used by boost.
export CPPFLAGS=$COMPILER_FLAGS  # Used by LZO.

FB_OS_VERSION=v2022.11.14.00
NPROC=$(getconf _NPROCESSORS_ONLN)
DEPENDENCY_DIR=${DEPENDENCY_DIR:-$(pwd)}

# Install distro packaged velox dependencies.
sudo dnf install -y \
    wget which \
    git \
    java-17-amazon-corretto java-17-amazon-corretto-devel \
    gcc gcc-c++ \
    ninja-build \
    openssl openssl-devel \
    libevent-devel \
    re2 \
    re2-devel \
    libzstd-devel \
    lz4-devel \
    libdwarf-devel \
    bzip2-devel \
    bzip2 \
    libevent \
    libevent-devel \
    zstd \
    lzo \
    lzo-devel \
    lz4 \
    lz4-devel \
    lz4-static \
    libzstd \
    libzstd-devel \
    libzstd-static \
    libicu \
    libicu-devel \
    boost \
    boost-devel \
    snappy \
    snappy-devel \
    curl-devel \
    cmake \
    libicu-devel \
    autoconf \
    automake \
    libtool \
    bison \
    flex \
    python3


# sudo_cmake_install compile and install a dependency
#
# This function uses cmake and ninja-build to compile and install
# a specified dependency. The caller is responsible for making sure
# that the code has been checked out and the current folder contains
# it.
#
# This function requires elevated privileges for the install part
function sudo_cmake_install {
  local NAME=$(basename "$(pwd)")
  local BINARY_DIR=_build
  CFLAGS=$(get_cxx_flags "$CPU_TARGET")

  if [ -d "${BINARY_DIR}" ] && prompt "Do you want to rebuild ${NAME}?"; then
    rm -rf "${BINARY_DIR}"
  fi
  mkdir -p "${BINARY_DIR}"
  CPU_TARGET="${CPU_TARGET:-avx}"

  # CMAKE_POSITION_INDEPENDENT_CODE is required so that Velox can be built into dynamic libraries \
  cmake -Wno-dev -B"${BINARY_DIR}" \
    -GNinja \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_CXX_STANDARD=17 \
    "${INSTALL_PREFIX+-DCMAKE_PREFIX_PATH=}${INSTALL_PREFIX-}" \
    "${INSTALL_PREFIX+-DCMAKE_INSTALL_PREFIX=}${INSTALL_PREFIX-}" \
    -DCMAKE_CXX_FLAGS="$CFLAGS" \
    -DBUILD_TESTING=OFF \
    "$@"

  # install a prebuilt project with elevated privileges
  # This is useful for systems where /usr/ is not writable
  local BINARY_DIR=_build
  sudo ninja-build -C "${BINARY_DIR}" install
}

function clean_dir {
  local DIRNAME=$(basename $1)
  if [ -d "${DIRNAME}" ]; then
    rm -rf "${DIRNAME}"
  fi
  mkdir ${DIRNAME}
}

function run_and_time {
  time "$@"
  { echo "+ Finished running $*"; } 2> /dev/null
}

function git_clone {
  local NAME=$1
  shift
  local REPO=$1
  shift
  local GIT_CLONE_PARAMS=$@
  local DIRNAME=$(basename $NAME)
  if [ -d "${DIRNAME}" ]; then
    rm -rf "${DIRNAME}"
  fi
  git clone -q $GIT_CLONE_PARAMS "${REPO}"
}

function prompt {
  (
    while true; do
      local input="${PROMPT_ALWAYS_RESPOND:-}"
      echo -n "$(tput bold)$* [Y, n]$(tput sgr0) "
      [[ -z "${input}" ]] && read input
      if [[ "${input}" == "Y" || "${input}" == "y" || "${input}" == "" ]]; then
        return 0
      elif [[ "${input}" == "N" || "${input}" == "n" ]]; then
        return 1
      fi
    done
  ) 2> /dev/null
}

function install_ccache {
  if [[ -v SKIP_CCACHE ]]
  then
      return 0
  fi
  local DIRNAME=$(basename "ccache-for-velox")
  clean_dir ${DIRNAME}
  pushd ./
  cd ${DIRNAME}

  wget https://github.com/ccache/ccache/releases/download/v4.7.4/ccache-4.7.4-linux-x86_64.tar.xz
  tar -xf ccache-4.7.4-linux-x86_64.tar.xz
  sudo cp ccache-4.7.4-linux-x86_64/ccache /usr/local/bin/

  popd
}

function install_boost {
  if [[ -v SKIP_BOOST ]]
  then
      return 0
  fi

  local DIRNAME=$(basename "boost-for-velox")
  clean_dir ${DIRNAME}

  pushd ./

  cd ${DIRNAME}

  local BOOST_VERSION=boost_1_81_0
  wget https://boostorg.jfrog.io/artifactory/main/release/1.81.0/source/${BOOST_VERSION}.tar.bz2
  bunzip2 ${BOOST_VERSION}.tar.bz2
  tar -xf ${BOOST_VERSION}.tar
  cd ${BOOST_VERSION}
  ./bootstrap.sh
  sudo env PATH=${PATH} ./b2 install

  popd
}

function install_doubleconversion {
  pushd ./
  github_checkout google/double-conversion v3.2.0
  sudo_cmake_install
  popd
}

function install_glog {
  pushd ./
  github_checkout google/glog v0.6.0
  sudo_cmake_install
  popd
}

function install_gflags {
  pushd ./
  github_checkout gflags/gflags v2.2.2
  sudo_cmake_install -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=ON -DINSTALL_HEADERS=ON
  popd
}

function install_gmock {
  pushd ./
  github_checkout google/googletest release-1.12.1
  sudo_cmake_install
  popd
}

function install_conda {
  pushd ./
  local MINICONDA_PATH=$(basename "miniconda-for-velox")

  cd ${DEPENDENCY_DIR}
  clean_dir "conda"
  pushd ./
  wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
  sh Miniconda3-latest-Linux-x86_64.sh -b -p $MINICONDA_PATH
  popd
  popd
}

function install_velox_deps {
  echo "Using ${DEPENDENCY_DIR} for installing dependencies"

  mkdir -p ${DEPENDENCY_DIR}

  # the following dependencies are managed by
  # 3rd party repositories
  pushd ./
  cd ${DEPENDENCY_DIR}

  run_and_time install_ccache
  popd

  # the following dependencies are managed by
  # github repositories
  run_and_time install_doubleconversion
  run_and_time install_glog
  run_and_time install_gflags
  run_and_time install_gmock
  run_and_time install_conda
}

(return 2> /dev/null) && return # If script was sourced, don't run commands.

(
  if [[ $# -ne 0 ]]; then
    for cmd in "$@"; do
      run_and_time "${cmd}"
    done
  else
    install_velox_deps
  fi
)

echo "All deps for Velox installed!"
echo "If gcc was installed from a 3rd party rpm (default), execute"
echo "$ source /opt/rh/devtoolset-11/enable"
echo "to setup the correct paths then execute make to compile velox"
