#工程名字
PROJECT_NAME = plugins

#目标名字
TARGET_NAME = plugins

#系统环境
UNAME_S = $(shell uname -s)

#伪目标
.PHONY: clean all target pre_build post_build
all : pre_build target post_build

#CFLAG
MYCFLAGS =

#需要定义的FLAG
MYCFLAGS += -Wsign-compare
MYCFLAGS += -Wno-sign-compare
MYCFLAGS += -Wno-unused-variable
MYCFLAGS += -Wno-unused-parameter
MYCFLAGS += -Wno-unknown-pragmas
MYCFLAGS += -Wno-unused-but-set-parameter
MYCFLAGS += -Wno-unused-function
MYCFLAGS += -Wno-unused-result
MYCFLAGS += -Wno-implicit-fallthrough
MYCFLAGS += -Wno-maybe-uninitialized

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
LIBS += -llua
#系统库
LIBS += -lm -ldl -lstdc++ -lpthread

#定义基础的编译选项
ifndef CC
CC = gcc
endif
ifndef CX
CX = c++
endif
CFLAGS = -g -O2 -Wall -Wno-deprecated -Wextra $(STDC) $(MYCFLAGS)
CXXFLAGS = -g -O2 -Wall -Wno-deprecated -Wextra $(STDCPP) $(MYCFLAGS)

#项目目录
ifndef SOLUTION_DIR
SOLUTION_DIR=./
endif

#临时文件目录
INT_DIR = $(SOLUTION_DIR)temp/$(PROJECT_NAME)

#目标文件前缀，定义则.so和.a加lib前缀，否则不加
PROJECT_PREFIX = lib

#目标定义
TARGET_DIR = $(SOLUTION_DIR)library
TARGET_STATIC =  $(TARGET_DIR)/$(PROJECT_PREFIX)$(TARGET_NAME).a
MYCFLAGS += -fPIC

#link添加.so目录
LDFLAGS += -L$(SOLUTION_DIR)bin
LDFLAGS += -L$(SOLUTION_DIR)library

#自动生成目标
OBJS =
#子目录
OBJS += $(patsubst $(SRC_DIR)/bson/%.c, $(INT_DIR)/bson/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/bson/*.c)))
OBJS += $(patsubst $(SRC_DIR)/bson/%.m, $(INT_DIR)/bson/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/bson/*.m)))
OBJS += $(patsubst $(SRC_DIR)/bson/%.cc, $(INT_DIR)/bson/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/bson/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/bson/%.cpp, $(INT_DIR)/bson/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/bson/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/laes/%.c, $(INT_DIR)/laes/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/laes/*.c)))
OBJS += $(patsubst $(SRC_DIR)/laes/%.m, $(INT_DIR)/laes/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/laes/*.m)))
OBJS += $(patsubst $(SRC_DIR)/laes/%.cc, $(INT_DIR)/laes/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/laes/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/laes/%.cpp, $(INT_DIR)/laes/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/laes/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/laoi/%.c, $(INT_DIR)/laoi/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/laoi/*.c)))
OBJS += $(patsubst $(SRC_DIR)/laoi/%.m, $(INT_DIR)/laoi/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/laoi/*.m)))
OBJS += $(patsubst $(SRC_DIR)/laoi/%.cc, $(INT_DIR)/laoi/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/laoi/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/laoi/%.cpp, $(INT_DIR)/laoi/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/laoi/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/lcodec/%.c, $(INT_DIR)/lcodec/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lcodec/*.c)))
OBJS += $(patsubst $(SRC_DIR)/lcodec/%.m, $(INT_DIR)/lcodec/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lcodec/*.m)))
OBJS += $(patsubst $(SRC_DIR)/lcodec/%.cc, $(INT_DIR)/lcodec/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lcodec/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/lcodec/%.cpp, $(INT_DIR)/lcodec/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lcodec/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/lcrypt/%.c, $(INT_DIR)/lcrypt/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lcrypt/*.c)))
OBJS += $(patsubst $(SRC_DIR)/lcrypt/%.m, $(INT_DIR)/lcrypt/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lcrypt/*.m)))
OBJS += $(patsubst $(SRC_DIR)/lcrypt/%.cc, $(INT_DIR)/lcrypt/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lcrypt/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/lcrypt/%.cpp, $(INT_DIR)/lcrypt/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lcrypt/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/lhttp/%.c, $(INT_DIR)/lhttp/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lhttp/*.c)))
OBJS += $(patsubst $(SRC_DIR)/lhttp/%.m, $(INT_DIR)/lhttp/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lhttp/*.m)))
OBJS += $(patsubst $(SRC_DIR)/lhttp/%.cc, $(INT_DIR)/lhttp/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lhttp/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/lhttp/%.cpp, $(INT_DIR)/lhttp/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lhttp/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/lrandom/%.c, $(INT_DIR)/lrandom/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lrandom/*.c)))
OBJS += $(patsubst $(SRC_DIR)/lrandom/%.m, $(INT_DIR)/lrandom/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lrandom/*.m)))
OBJS += $(patsubst $(SRC_DIR)/lrandom/%.cc, $(INT_DIR)/lrandom/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lrandom/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/lrandom/%.cpp, $(INT_DIR)/lrandom/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lrandom/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/lstdfs/%.c, $(INT_DIR)/lstdfs/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lstdfs/*.c)))
OBJS += $(patsubst $(SRC_DIR)/lstdfs/%.m, $(INT_DIR)/lstdfs/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lstdfs/*.m)))
OBJS += $(patsubst $(SRC_DIR)/lstdfs/%.cc, $(INT_DIR)/lstdfs/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lstdfs/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/lstdfs/%.cpp, $(INT_DIR)/lstdfs/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lstdfs/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/ltimer/%.c, $(INT_DIR)/ltimer/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/ltimer/*.c)))
OBJS += $(patsubst $(SRC_DIR)/ltimer/%.m, $(INT_DIR)/ltimer/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/ltimer/*.m)))
OBJS += $(patsubst $(SRC_DIR)/ltimer/%.cc, $(INT_DIR)/ltimer/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/ltimer/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/ltimer/%.cpp, $(INT_DIR)/ltimer/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/ltimer/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/lyyjson/%.c, $(INT_DIR)/lyyjson/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lyyjson/*.c)))
OBJS += $(patsubst $(SRC_DIR)/lyyjson/%.m, $(INT_DIR)/lyyjson/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lyyjson/*.m)))
OBJS += $(patsubst $(SRC_DIR)/lyyjson/%.cc, $(INT_DIR)/lyyjson/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lyyjson/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/lyyjson/%.cpp, $(INT_DIR)/lyyjson/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lyyjson/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/lzset/%.c, $(INT_DIR)/lzset/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lzset/*.c)))
OBJS += $(patsubst $(SRC_DIR)/lzset/%.m, $(INT_DIR)/lzset/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lzset/*.m)))
OBJS += $(patsubst $(SRC_DIR)/lzset/%.cc, $(INT_DIR)/lzset/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lzset/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/lzset/%.cpp, $(INT_DIR)/lzset/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/lzset/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/mongo/%.c, $(INT_DIR)/mongo/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/mongo/*.c)))
OBJS += $(patsubst $(SRC_DIR)/mongo/%.m, $(INT_DIR)/mongo/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/mongo/*.m)))
OBJS += $(patsubst $(SRC_DIR)/mongo/%.cc, $(INT_DIR)/mongo/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/mongo/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/mongo/%.cpp, $(INT_DIR)/mongo/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/mongo/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/protobuf/%.c, $(INT_DIR)/protobuf/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/protobuf/*.c)))
OBJS += $(patsubst $(SRC_DIR)/protobuf/%.m, $(INT_DIR)/protobuf/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/protobuf/*.m)))
OBJS += $(patsubst $(SRC_DIR)/protobuf/%.cc, $(INT_DIR)/protobuf/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/protobuf/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/protobuf/%.cpp, $(INT_DIR)/protobuf/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/protobuf/*.cpp)))
#子目录
OBJS += $(patsubst $(SRC_DIR)/tools/%.c, $(INT_DIR)/tools/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/tools/*.c)))
OBJS += $(patsubst $(SRC_DIR)/tools/%.m, $(INT_DIR)/tools/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/tools/*.m)))
OBJS += $(patsubst $(SRC_DIR)/tools/%.cc, $(INT_DIR)/tools/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/tools/*.cc)))
OBJS += $(patsubst $(SRC_DIR)/tools/%.cpp, $(INT_DIR)/tools/%.o, $(filter-out $(EXCLUDE), $(wildcard $(SRC_DIR)/tools/*.cpp)))
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

$(TARGET_STATIC) : $(OBJS)
	ar rcs $@ $(OBJS)
	ranlib $@

#target伪目标
target : $(TARGET_STATIC)

#clean伪目标
clean :
	rm -rf $(INT_DIR)

#预编译
pre_build:
	mkdir -p $(INT_DIR)
	mkdir -p $(TARGET_DIR)
	mkdir -p $(INT_DIR)/bson
	mkdir -p $(INT_DIR)/laes
	mkdir -p $(INT_DIR)/laoi
	mkdir -p $(INT_DIR)/lcodec
	mkdir -p $(INT_DIR)/lcrypt
	mkdir -p $(INT_DIR)/lhttp
	mkdir -p $(INT_DIR)/lrandom
	mkdir -p $(INT_DIR)/lstdfs
	mkdir -p $(INT_DIR)/ltimer
	mkdir -p $(INT_DIR)/lyyjson
	mkdir -p $(INT_DIR)/lzset
	mkdir -p $(INT_DIR)/mongo
	mkdir -p $(INT_DIR)/protobuf
	mkdir -p $(INT_DIR)/tools

#后编译
post_build:
