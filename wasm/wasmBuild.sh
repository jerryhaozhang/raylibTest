#!/bin/bash
set -euo pipefail

EMSDK="/Users/jerry/cProgram/emsdk"
PROJECT="/Users/jerry/cProgram/raylibTest/sample0"
OUTDIR="out"
RAYLIB_ROOT="/Users/jerry/cProgram/raylibTest/lib/raylib"
RAYLIB_A=""   # 构建后自动探测
SHELL_FILE="" # 自动探测
RESOURCE_DIR="/Users/jerry/cProgram/raylibTest/resources"

SRC_FILES=()
USER_SRC=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --src) SRC_FILES+=("$2"); USER_SRC=true; shift 2;;
    --resources) RESOURCE_DIR="$2"; shift 2;;
    -h|--help) echo "参数: --src FILE 可重复, --resources DIR"; exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done
if ! $USER_SRC; then SRC_FILES=("main.c"); fi

cd "$EMSDK"
source emsdk_env.sh

build_raylib_web() {
  echo "构建 wasm 版 raylib (官方 Makefile)..."
  if [[ ! -d "$RAYLIB_ROOT/src" || ! -f "$RAYLIB_ROOT/src/Makefile" ]]; then
    echo "错误: 缺少 raylib 源或 '$RAYLIB_ROOT/src/Makefile'"
    exit 1
  fi

  make -C "$RAYLIB_ROOT/src" clean >/dev/null 2>&1 || true
  make -C "$RAYLIB_ROOT/src" PLATFORM=PLATFORM_WEB || { echo "raylib 构建失败"; exit 1; }

  # 产物探测：优先 web 名称
  if [[ -f "$RAYLIB_ROOT/src/libraylib.web.a" ]]; then
    RAYLIB_A="$RAYLIB_ROOT/src/libraylib.web.a"
  elif [[ -f "$RAYLIB_ROOT/src/libraylib.a" ]]; then
    RAYLIB_A="$RAYLIB_ROOT/src/libraylib.a"
  else
    echo "错误: 未找到生成库 '$RAYLIB_ROOT/src/libraylib.web.a' 或 '$RAYLIB_ROOT/src/libraylib.a'"
    exit 1
  fi

  # 校验为可用于 Emscripten 链接的对象(接受 WebAssembly 或 LLVM bitcode)
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null
  first_obj=""
  if llvm-ar t "$RAYLIB_A" >/dev/null 2>&1; then
    first_obj="$(llvm-ar t "$RAYLIB_A" | head -n1 || true)"
  fi
  if [[ -n "$first_obj" ]]; then
    llvm-ar x "$RAYLIB_A" "$first_obj" || true
    if [[ -f "$first_obj" ]]; then
      kind="$(file -b "$first_obj" || true)"
      if ! echo "$kind" | grep -Eqi "WebAssembly|LLVM"; then
        popd >/dev/null
        rm -rf "$tmpdir"
        echo "错误: 构建产物对象类型不受支持: $kind"
        exit 1
      fi
    fi
  fi
  popd >/dev/null
  rm -rf "$tmpdir"
  echo "完成: '$RAYLIB_A'"
}

detect_shell() {
  if [[ -f "$RAYLIB_ROOT/src/shell.html" ]]; then
    SHELL_FILE="$RAYLIB_ROOT/src/shell.html"
  elif [[ -f "$RAYLIB_ROOT/shell.html" ]]; then
    SHELL_FILE="$RAYLIB_ROOT/shell.html"
  else
    SHELL_FILE=""
  fi
}

build_raylib_web
detect_shell

cd "$PROJECT/src"
mkdir -p "../$OUTDIR"

COMMON_ARGS=(
  -o "../$OUTDIR/index.html"
  "${SRC_FILES[@]}"
  -Os -Wall "$RAYLIB_A"
  -I. -I "$RAYLIB_ROOT/src"
  -L. -L "$RAYLIB_ROOT/src"
  -s USE_GLFW=3
  -s ASYNCIFY
  -s TOTAL_STACK=64MB
  -s INITIAL_MEMORY=128MB
  -s ASSERTIONS
  -DPLATFORM_WEB
)

# 仅当存在 shell.html 时添加
if [[ -n "$SHELL_FILE" ]]; then
  COMMON_ARGS+=( --shell-file "$SHELL_FILE" )
fi

## 资源预加载与 FS
#if [[ -d "$RESOURCE_DIR" ]]; then
#  emcc "${COMMON_ARGS[@]}" --preload-file "$RESOURCE_DIR" -s FORCE_FILESYSTEM=1
#else
#  emcc "${COMMON_ARGS[@]}"
#fi

# 资源预加载与 FS（在 cd "$PROJECT/src" 之后）
MOUNT_NAME="resources"
HOST_RES_DIR=""
if [[ -d "../$RESOURCE_DIR" ]]; then
  # 资源在项目根或上级
  HOST_RES_DIR="../$RESOURCE_DIR"
elif [[ -d "$RESOURCE_DIR" ]]; then
  # 资源就在 src 下
  HOST_RES_DIR="$RESOURCE_DIR"
else
  HOST_RES_DIR=""
fi

if [[ -n "$HOST_RES_DIR" ]]; then
  # 挂载为虚拟路径 /resources，代码可用 "resources/xxx" 或 "/resources/xxx"
  emcc "${COMMON_ARGS[@]}" --preload-file "${HOST_RES_DIR}@${MOUNT_NAME}" -s FORCE_FILESYSTEM=1
else
  echo "警告: 未找到资源目录 '${RESOURCE_DIR}' 或 '../${RESOURCE_DIR}'，跳过预加载"
  emcc "${COMMON_ARGS[@]}"
fi


cd "../$OUTDIR"
emrun index.html
