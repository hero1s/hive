empty:
	@echo "====No target! Please specify a target to make!"
	@echo "====If you want to compile all targets, use 'make server'"
	@echo "===='make all', which shoule be the default target is unavailable for UNKNOWN reaseon now."

CUR_DIR = $(shell pwd)/

.PHONY: clean all server  share lua luaext core

all: clean server 

server:  share lua luaext core

clean:
	rm -rf temp;

core:
	cd core/luabus; make -j4 SOLUTION_DIR=$(CUR_DIR) -f luabus.mak;
	cd core/plugins; make -j4 SOLUTION_DIR=$(CUR_DIR) -f lplugins.mak;
	cd core/hive; make -j4 SOLUTION_DIR=$(CUR_DIR) -f hive.mak;

lua:
	cd extend/lua; make -j4 SOLUTION_DIR=$(CUR_DIR) -f lualib.mak;
	cd extend/lua; make -j4 SOLUTION_DIR=$(CUR_DIR) -f lua.mak;
	cd extend/lua; make -j4 SOLUTION_DIR=$(CUR_DIR) -f luac.mak;

luaext:
	cd extend/lcurl; make -j4 SOLUTION_DIR=$(CUR_DIR) -f lcurl.mak;
	cd extend/ldetour; make -j4 SOLUTION_DIR=$(CUR_DIR) -f ldetour.mak;
	cd extend/ljson; make -j4 SOLUTION_DIR=$(CUR_DIR) -f ljson.mak;
	cd extend/lmdb; make -j4 SOLUTION_DIR=$(CUR_DIR) -f lmdb.mak;
	cd extend/luaxlsx; make -j4 SOLUTION_DIR=$(CUR_DIR) -f luaxlsx.mak;
	cd extend/luaxml; make -j4 SOLUTION_DIR=$(CUR_DIR) -f luaxml.mak;
	cd extend/lyaml; make -j4 SOLUTION_DIR=$(CUR_DIR) -f lyaml.mak;

share:
	cd extend/mimalloc; make -j4 SOLUTION_DIR=$(CUR_DIR) -f mimalloc.mak;

