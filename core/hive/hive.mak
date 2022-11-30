#工程名字
PROJECT_NAME = hive

#目标名字
TARGET_NAME = hive

#系统环境
UNAME_S = $(shell uname -s)

#伪目标
.PHONY: clean all target pre_build post_build
all : pre_build target post_build

#CFLAG
MYCFLAGS =

#需要定义的FLAG
MYCFLAGS += -fpermissive
MYCFLAGS += -Wno-unused-variable
MYCFLAGS += -Wno-unused-parameter
MYCFLAGS += -Wno-unused-but-set-parameter
MYCFLAGS += -Wno-unused-function
MYCFLAGS += -Wno-unused-result
MYCFLAGS += -Wno-sign-compare

#c标准库版本
#gnu99/gnu11/gnu17
STDC = -std=gnu99

#c++标准库版本
#c++11/c++14/c++17/c++20
STDCPP = -std=c++17

#需要的include目录
MYCFLAGS += -I../../extend/lua/lua
MYCFLAGS += -I../../extend/fmt/include
MYCFLAGS += -I../../extend/luakit/include
MYCFLAGS += -I../../extend/utility
MYCFLAGS += -I../plugins/src

#需要定义的选项
MYCFLAGS += -DFMT_HEADER_ONLY

#LDFLAGS
LDFLAGS =


#源文件路径
SRC_DIR = src

#需要排除的源文件,目录基于$(SRC_DIR)
EXCLUDE =

#需要连接的库文件
LIBS =
#是否启用mimalloc库
LIBS += -lmimalloc
MYCFLAGS += -I$(SOLUTION_DIR)extend/mimalloc/mimalloc/include -include ../../mimalloc-ex.h
#自定义库
LIBS += -lluabus
LIBS += -lluna
LIBS += -lplugins
LIBS += -llua
ifeq ($(UNAME_S), Linux)
LIBS += -lstdc++fs
endif
#系统库
LIBS += -lm -ldl -lstdc++ -lpthread

#定义基础的编译选项
ifndef CC
CC = gcc
endif
ifndef CX
CX = c++
endif
CFLAGS = -g -O2 -Wall -Wno-deprecated -Wextra -Wno-unknown-pragmas $(STDC) $(MYCFLAGS)
CXXFLAGS = -g -O2 -Wall -Wno-deprecated -Wextra -Wno-unknown-pragmas $(STDCPP) $(MYCFLAGS)

#项目目录
ifndef SOLUTION_DIR
SOLUTION_DIR=./
endif

#临时文件目录
INT_DIR = $(SOLUTION_DIR)temp/$(PROJECT_NAME)


#目标定义
TARGET_DIR = $(SOLUTION_DIR)bin
TARGET_EXECUTE =  $(TARGET_DIR)/$(TARGET_NAME)

#link添加.so目录
LDFLAGS += -L$(SOLUTION_DIR)bin
LDFLAGS += -L$(SOLUTION_DIR)library

#自动生成目标
OBJS =
#子目录
OBJS += $(patsubst $(SRC_DIR)/lualog/%.c, $(INT_DIR)/lualog/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lualog/*.c)))
OBJS += $(patsubst $(SRC_DIR)/lualog/%.m, $(INT_DIR)/lualog/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lualog/*.m)))
OBJS += $(patsubst $(SRC_DIR)/lualog/%.cc, $(INT_DIR)/lualog/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lualog/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/lualog/%.cpp, $(INT_DIR)/lualog/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lualog/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/worker/%.c, $(INT_DIR)/worker/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/worker/*.c)))
OBJS += $(patsubst $(SRC_DIR)/worker/%.m, $(INT_DIR)/worker/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/worker/*.m)))
OBJS += $(patsubst $(SRC_DIR)/worker/%.cc, $(INT_DIR)/worker/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/worker/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/worker/%.cpp, $(INT_DIR)/worker/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/worker/*.cpp)))
#根目录
OBJS += $(patsubst $(SRC_DIR)/%.c, $(INT_DIR)/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/*.c)))
OBJS += $(patsubst $(SRC_DIR)/%.m, $(INT_DIR)/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/*.m)))
OBJS += $(patsubst $(SRC_DIR)/%.cc, $(INT_DIR)/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/%.cpp, $(INT_DIR)/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/*.cpp)))

# 编译所有源文件
$(INT_DIR)/%.o : $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@
$(INT_DIR)/%.o : $(SRC_DIR)/%.m
	$(CC) $(CFLAGS) -c $< -o $@
$(INT_DIR)/%.o : $(SRC_DIR)/%.cc
	$(CX) $(CXXFLAGS) -c $< -o $@
$(INT_DIR)/%.o : $(SRC_DIR)/%.cpp
	$(CX) $(CXXFLAGS) -c $< -o $@

$(TARGET_EXECUTE) : $(OBJS)
	$(CC) -o $@  $(OBJS) $(LDFLAGS) $(LIBS)

#target伪目标
target : $(TARGET_EXECUTE)

#clean伪目标
clean :
	rm -rf $(INT_DIR)

#预编译
pre_build:
	mkdir -p $(INT_DIR)
	mkdir -p $(TARGET_DIR)
	mkdir -p $(INT_DIR)/lualog
	mkdir -p $(INT_DIR)/worker

#后编译
post_build:
