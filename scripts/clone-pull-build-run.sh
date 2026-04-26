#!/usr/bin/env bash
# Copyright 2025 The contributors of Goinfer.
# SPDX-License-Identifier: MIT

help='
Usage:

  ./clone-pull-build-run.sh [goinfer flags]

This script git-clone (git-pull) and builds llama.cpp with best optimizations.
The script also generates the configuration based on the discovered GUFF files.
Finally the script runs goinfer with the provided [goinfer flags] if any.

This script can be used:
- once, to setup all the dependencies and the configuration files
- daily, to update the llama.cpp source code and rebuild it
  (only if a new commit is detected)

For better reproducibility, you can specify the tag or branch:

  tag=b7777     ./clone-pull-build-run.sh`
  branch=master ./clone-pull-build-run.sh`

If you have already your `llama-server` (or compatible fork),
set `export GI_LLAMA_EXE=/home/me/path/llama-server`.
This env. var. disables the clone/pull/build of llama.cpp.

If the script finds `*.gguf` model directories you prefer to ignore,
set the GI_MODELS_DIR. This also speeds up the script (disables GUFF files search).

  export GI_MODELS_DIR=/home/me/models:/home/me/other/path

The [goinfer flags] are passed to goinfer.
For example, to run Goinfer without API key:

  ~/repo/goinfer/scripts/clone-pull-build-run.sh -no-api-key

One-line example:

  git pull && GI_LLAMA_EXE=~/path/llama-server GI_MODELS_DIR=~/path/models ./clone-pull-build-run.sh -no-api-key
'

# Safe bash
set -e                   # stop the script if any command returns a non‑zero status
set -u                   # unset variable is an error => exit
set -o pipefail          # pipeline fails if any of its components fails
set -o noclobber         # prevent accidental file overwriting with > redirection
shopt -s inherit_errexit # apply these restrictions to $(command substitution)

# Color logs
err() { set +x; echo >&2 -e "\033[34m$(date +%H:%M)\033[m \033[31m" "$@" "\033[m"; }
log() { set +x; echo >&2 -e "\033[34m$(date +%H:%M)\033[m \033[32m" "$@" "\033[m"; }
lop() { log "repo ${repo:-none} - $@"; set -x; } # lop stands for LOg rePo

# print the script line number if something goes wrong
set -E
trap 'set +x; s=$?; err "status=$? at ${BASH_SOURCE[0]}:$LINENO" >&2; exit $s' ERR

# Git repositories
goinfer_dir="$(  cd "${BASH_SOURCE[0]%/*}/.."  &&  pwd)"
root_dir="$(     cd "${goinfer_dir}/.."        &&  pwd)"
llamaCpp_dir="${root_dir}/llama.cpp"

# CPU flags used to build both llama.cpp and goinfer
flags="$(grep "^flags" -wm1 /proc/cpuinfo) " # trailing space required

case "${1:-}" in
  -h|--help)
    echo "$help"
    exit
    ;;
esac

command -v npm    >/dev/null || { err REQUIRED: install npm    && exit 1; }
command -v git    >/dev/null || { err REQUIRED: install git    && exit 1; }
command -v go     >/dev/null || { err REQUIRED: install go     && exit 1; }
command -v cmake  >/dev/null || { err REQUIRED: install cmake  && exit 1; }
command -v ninja  >/dev/null || { err REQUIRED: install ninja  && exit 1; }
command -v ccache >/dev/null || { err REQUIRED: install ccache && exit 1; }

do_llamaCpp() {
  cd "$root_dir"

  clone_checkout_pull ggml-org/llama.cpp "${branch:-master}" "${tag:-}"

  build_llamaCpp
}

# clone_checkout_pull sets the variable build_reason=... to trigger the build
clone_checkout_pull() {
  local repo=$1
  local branch=$2
  local tag=$3

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


build_llamaCpp() {
  [[ -n "$build_reason" ]] || { [[ -f build/bin/llama-server ]] || build_reason="missing build/bin/llama-server" ; }
  [[ -z "$build_reason" ]] || (
    log "build llama.cpp because $build_reason"
    rm -rf build/  # this guarantees a clean build, ccache will restore deleted files
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
      -D BUILD_SHARED_LIBS=${BUILD_SHARED_LIBS:-ON}                                           \
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
      -D GGML_BACKEND_DL=${GGML_BACKEND_DL:-ON}                                               \
      -D GGML_BLAS=${GGML_BLAS:-ON}                                                           \
      -D GGML_CCACHE=${GGML_CCACHE:-ON}                                                       \
      -D GGML_CPU_ALL_VARIANTS=${GGML_CPU_ALL_VARIANTS:-ON}                                   \
      -D GGML_CUDA_ENABLE_UNIFIED_MEMORY=${GGML_CUDA_ENABLE_UNIFIED_MEMORY:-ON}               \
      -D GGML_CUDA_F16=${GGML_CUDA_F16:-ON}                                                   \
      -D GGML_CUDA_FA_ALL_QUANTS=${GGML_CUDA_FA_ALL_QUANTS:-ON}                               \
      -D GGML_CUDA=${GGML_CUDA:-$(command -v nvcc >/dev/null && echo ON || echo OFF)}         \
      -D GGML_LTO=${GGML_LTO:-ON}                                                             \
      -D GGML_NATIVE=${GGML_NATIVE:-ON}                                                       \
      -D GGML_STATIC=${GGML_STATIC:-OFF}                                                      \
      -D LLAMA_BUILD_EXAMPLES=${LLAMA_BUILD_EXAMPLES:-ON}                                     \
      -D LLAMA_BUILD_TESTS=${LLAMA_BUILD_TESTS:-OFF}                                          \
      -D LLAMA_BUILD_TOOLS=${LLAMA_BUILD_TOOLS:-ON}                                           \
      -D LLAMA_LLGUIDANCE=${LLAMA_LLGUIDANCE:-OFF}                                            \
      .
      # -D GGML_SCHED_MAX_COPIES=${GGML_SCHED_MAX_COPIES:-1}                                  \
    cmake --build build/ --config Release --clean-first --target llama-server llama-bench
  )
}

# if GI_MODELS_DIR is unset => discover the parent folders of the GUFF files:
#   - find the files *.gguf in $HOME and /mnt directories
#   - -printf their folders (%h) separated by nul character `\0`
#     (support folder names containing newline characters)
#   - sort them, -u to keep a unique copy of each folder (`z` = input is `\0` separated)
#   - while read xxx; do xxx; done  =>  keep the parent folders
#   - echo $d: prints each parent folder separated by : (`-n` no newline)
GI_MODELS_DIR="${GI_MODELS_DIR:-$(log "search for *.gguf in $HOME and /mnt"; 
p=; { find "$HOME" /mnt -type f -name '*.gguf' -printf '%h\0' || : ; } | sort -zu |
while IFS= read -rd '' d;do [[ $p && $d == "$p"/* ]] && continue;echo -n "$d:";p=$d;done)}"

export GI_MODELS_DIR=${GI_MODELS_DIR:?GI_MODELS_DIR is empty: Download a model file *.gguf or set GI_MODELS_DIR}

# clone/pull/build llama.cpp if GI_LLAMA_EXE is unset/empty
export GI_LLAMA_EXE="${GI_LLAMA_EXE:-"$(do_llamaCpp >&2 && \ls -1 "$llamaCpp_dir/build/bin/llama-server")"}"

cd "$goinfer_dir"

build_reason=
[[ -f proxy/ui_dist/favicon.ico ]] || build_reason="missing proxy/ui_dist/favicon.ico"
[[ -z "$build_reason" ]] || (
  log "build Web UI because $build_reason"
  # we may: rm proxy/ui_dist/
  cd ui
  pwd
  set -x
  npm ci --prefer-offline --no-audit --no-fund # --omit=dev (--omit=dev prevents the installation of tsc)
  npm run build
)

(
  log build goinfer with CPU-optimizations
  case "$flags" in
      *" avx512f "*)  export GOAMD64=v4;;
      *" avx2 "*)     export GOAMD64=v3;;
      *" sse2 "*)     export GOAMD64=v2;;
  esac
  pwd
  rm -f ./goinfer
  set -x
  go build .
)

(
  log "generate config (if missing) and run Goinfer"
  set -x
  export GIN_MODE="${GIN_MODE:-release}"
  ./goinfer "$@"
)
