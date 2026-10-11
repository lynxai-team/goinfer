#!/usr/bin/env bash
# Copyright 2025 The contributors of Goinfer.
# SPDX-License-Identifier: MIT

help='
Usage:

  ./clone-pull-build.sh

This script does:
- git clone (or pull) of the llama.cpp repo
- build llama-server with CUDA and best optimizations

Optional: Specify the Git tag or branch:
  tag=v0.6.0    ./clone-pull-build.sh
  branch=master ./clone-pull-build.sh
'

# Safe bash
set -e                   # stop the script if any command returns a non‑zero status
set -u                   # unset variable is an error => exit
set -o pipefail          # pipeline fails if any of its components fails
set -o noclobber         # prevent accidental file overwriting with > redirection
shopt -s inherit_errexit # apply these restrictions to $(command substitution)

# Color logs
err() { set +x; echo >&2 -e "\e[34m$(date +%H:%M)\e[m \e[31m" "$@" "\e[m"; }
log() { set +x; echo >&2 -e "\e[34m$(date +%H:%M)\e[m \e[32m" "$@" "\e[m"; }
lop() { log "repo ${repo:-none} - $@"; set -x; } # lop stands for LOg rePo

# print the script line number if something goes wrong
set -E
trap 'set +x; s=$?; err "status=$? at ${BASH_SOURCE[0]}:$LINENO" >&2; exit $s' ERR


case "${1:-}" in
  -h|--help)
    echo "$help"
    exit
    ;;
esac

repo=ggml-org/llama.cpp  
branch="${branch:-master}"
tag="${tag:-}"

command -v git    >/dev/null || { err REQUIRED: install git    && exit 1; }
command -v cmake  >/dev/null || { err REQUIRED: install cmake  && exit 1; }
command -v ninja  >/dev/null || { err REQUIRED: install ninja  && exit 1; }
command -v ccache >/dev/null || { err REQUIRED: install ccache && exit 1; }

# clone_checkout_pull sets the variable build_reason=... to trigger the build
clone_checkout_pull() {
  build_reason=clone
  [ -d "${repo#*/}" ] && build_reason= || 
    ( pwd; lop clone; git clone https://github.com/"$repo" )
    
  cd "${repo#*/}"
  pwd
  
  ( lop fetch; git fetch --all --prune --tags )
  
  if [[ -n "$tag" ]]
  then
    build_reason="tag: $tag"
    ( lop "checkout $tag"; git checkout "$tag" )
  else
    # lop "switch $branch"; git switch -C "$branch" origin/"$branch" )
    ( lop "switch $branch"; git switch "$branch" )
    local="$( git rev-parse HEAD)"
    remote="$(git rev-parse "@{upstream}")"
    if [[ "$local" != "$remote" ]]
    then
      build_reason="new commit: $(git log -1 --pretty=format:%f)"
      ( lop "$build_reason"; git pull --ff-only ) || 
      ( lop "discard local changes"; git reset --hard origin/"$branch" )
    fi
  fi
  
  ( set -x; git status --short )
}


build_llama() {
  [[ -n "$build_reason" ]] || { [[ -f build/bin/llama-server ]] || build_reason="missing build/bin/llama-server" ; }
  [[ -z "$build_reason" ]] || (
    log "build llama.cpp because $build_reason"
    rm -rf build/  # this guarantees a clean build, ccache will restore deleted files
    # CPU flags
    flags="$(grep "^flags" -wm1 /proc/cpuinfo) " # trailing space required
    GGML_AVX=$(        [[ "$flags" == *" avx "*         ]] && echo ON || echo OFF)
    GGML_AVX2=$(       [[ "$flags" == *" avx2 "*        ]] && echo ON || echo OFF)
    GGML_AVX_VNNI=$(   [[ "$flags" == *" vnni "*        ]] && echo ON || echo OFF)
    GGML_AVX512=$(     [[ "$flags" == *" avx512f "*     ]] && echo ON || echo OFF)
    GGML_AVX512_BF16=$([[ "$flags" == *" avx512_bf16 "* ]] && echo ON || echo OFF)
    GGML_AVX512_VBMI=$([[ "$flags" == *" avx512_vbmi "* ]] && echo ON || echo OFF)
    GGML_AVX512_VNNI=$([[ "$flags" == *" avx512_vnni "* ]] && echo ON || echo OFF)
    GGML_BMI2=$(       [[ "$flags" == *" bmi2 "*        ]] && echo ON || echo OFF)
    GGML_SSE42=$(      [[ "$flags" == *" sse4_2 "*      ]] && echo ON || echo OFF)
    pwd
    set -x
    # generate the Ninja files (faster than Makefile)
    cmake -G Ninja                                                                            \
      -B build/                                                                               \
      -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS:-OFF}                                          \
      -D CMAKE_BUILD_TYPE=Release                                                             \
      -D CMAKE_CUDA_ARCHITECTURES=${CMAKE_CUDA_ARCHITECTURES:-86}                             \
      -D CMAKE_EXE_LINKER_FLAGS=${CMAKE_EXE_LINKER_FLAGS:-"-Wl,--allow-shlib-undefined,-flto"}\
      -D GGML_AVX=$GGML_AVX                                                                   \
      -D GGML_AVX2=$GGML_AVX2                                                                 \
      -D GGML_AVX_VNNI=$GGML_AVX_VNNI                                                         \
      -D GGML_AVX512=$GGML_AVX512                                                             \
      -D GGML_AVX512_BF16=$GGML_AVX512_BF16                                                   \
      -D GGML_AVX512_VBMI=$GGML_AVX512_VBMI                                                   \
      -D GGML_AVX512_VNNI=$GGML_AVX512_VNNI                                                   \
      -D GGML_BMI2=$GGML_BMI2                                                                 \
      -D GGML_SSE42=$GGML_SSE42                                                               \
      -D GGML_BACKEND_DL=${GGML_BACKEND_DL:-OFF}                                              \
      -D GGML_BLAS=${GGML_BLAS:-OFF}                                                          \
      -D GGML_CCACHE=${GGML_CCACHE:-ON}                                                       \
      -D GGML_CPU_ALL_VARIANTS=${GGML_CPU_ALL_VARIANTS:-OFF}                                  \
      -D GGML_CUDA_ENABLE_UNIFIED_MEMORY=${GGML_CUDA_ENABLE_UNIFIED_MEMORY:-OFF}              \
      -D GGML_CUDA_F16=${GGML_CUDA_F16:-ON}                                                   \
      -D GGML_CUDA_FA_QUANTS=${GGML_CUDA_FA_ALL_QUANTS:-all}                                  \
      -D GGML_CUDA=${GGML_CUDA:-$(command -v nvcc >/dev/null && echo ON || echo OFF)}         \
      -D GGML_LTO=${GGML_LTO:-ON}                                                             \
      -D GGML_NATIVE=${GGML_NATIVE:-ON}                                                       \
      -D GGML_SCHED_MAX_COPIES=${GGML_SCHED_MAX_COPIES:-1}                                    \
      -D GGML_STATIC=${GGML_STATIC:-ON}                                                       \
      -D LLAMA_BUILD_EXAMPLES=${LLAMA_BUILD_EXAMPLES:-ON}                                     \
      -D LLAMA_BUILD_TESTS=${LLAMA_BUILD_TESTS:-OFF}                                          \
      -D LLAMA_BUILD_TOOLS=${LLAMA_BUILD_TOOLS:-ON}                                           \
      -D LLAMA_LLGUIDANCE=${LLAMA_LLGUIDANCE:-OFF}                                            \
      .
    cmake --build build/ --config Release --clean-first --target llama-server
  )
}

# Git repositories
goinfer_dir="$(cd "${BASH_SOURCE[0]%/*}/.."  &&  pwd)"
root_dir="$(   cd "${goinfer_dir}/.."        &&  pwd)"
cd "$root_dir"

clone_checkout_pull

build_llama
