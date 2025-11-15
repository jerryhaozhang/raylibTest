# makefile
CC ?= cc
CFLAGS ?= -Wall -std=c99

UNAME_S := $(shell uname -s)
PKG_CONFIG := $(shell command -v pkg-config 2>/dev/null)
HB_PREFIX := $(shell brew --prefix 2>/dev/null)

# 源与目标
SRC := sample0/src/main.c
TARGET := game

# raylib 源目录（当前项目内）
RAYLIB_SRC_DIR := lib/raylib/src
RAYLIB_NATIVE_LIB := $(RAYLIB_SRC_DIR)/libraylib.a

# 平台框架
ifeq ($(UNAME_S),Darwin)
  MACOS_FRAMEWORKS := -framework Cocoa -framework IOKit -framework CoreVideo -framework OpenGL -framework CoreAudio -framework AudioToolbox
endif

# pkg-config 可用性
ifeq ($(PKG_CONFIG),)
  USE_PKGCONFIG := 0
else
  USE_PKGCONFIG := $(shell $(PKG_CONFIG) --exists raylib && echo 1 || echo 0)
endif

# 选择依赖与参数
ifeq ($(USE_PKGCONFIG),1)
  RAYLIB_CFLAGS := $(shell $(PKG_CONFIG) --cflags raylib)
  RAYLIB_LIBS   := $(shell $(PKG_CONFIG) --libs raylib)
  TARGET_DEPS   :=
else
  ifneq ($(HB_PREFIX),)
    # Homebrew 安装
    RAYLIB_CFLAGS := -I$(HB_PREFIX)/include
    RAYLIB_LIBS   := -L$(HB_PREFIX)/lib -lraylib $(MACOS_FRAMEWORKS)
    TARGET_DEPS   :=
  else
    # 本地源码构建（自动生成原生静态库）
    RAYLIB_CFLAGS := -I$(RAYLIB_SRC_DIR)
    RAYLIB_LIBS   := $(MACOS_FRAMEWORKS)
    TARGET_DEPS   := $(RAYLIB_NATIVE_LIB)
  endif
endif

all: $(TARGET)

# 仅在需要本地构建时触发
$(RAYLIB_NATIVE_LIB):
	$(MAKE) -C $(RAYLIB_SRC_DIR) clean
	$(MAKE) -C $(RAYLIB_SRC_DIR) PLATFORM=PLATFORM_DESKTOP RAYLIB_LIBTYPE=STATIC

$(TARGET): $(SRC) $(TARGET_DEPS)
	$(CC) $(CFLAGS) $(RAYLIB_CFLAGS) -o $@ $< $(TARGET_DEPS) $(RAYLIB_LIBS)

clean:
	$(RM) $(TARGET)
