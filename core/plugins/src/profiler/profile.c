
#ifndef WIN32
#include <unistd.h>
#endif // !WIN32
#include <lauxlib.h>
#include <time.h> 
#include <stdlib.h>
#include <assert.h>
#include <stdbool.h>
#include <string.h>


#include "profile.h"
#include "imap.h"

#define get_item(context, idx)    &((context)->record_pool.pool[idx])
#define cap_item(context)         ((context)->record_pool.cap)

#define NANOSEC                     1000000000
#define MICROSEC                    1000000
#define MAX_SOURCE_LEN              128
#define MAX_NAME_LEN                32
#define MAX_CALL_SIZE               1024
#define MAX_CI_SIZE                 256
#define DEFAULT_POOL_ITEM_COUNT     64

struct record_item {
    const void* point;
    int count;
    char source[MAX_SOURCE_LEN];
    char name[MAX_NAME_LEN];
    int line;
    char flag;
    uint64_t all_cost;
    double ave_cost;
    double percent;
};

struct call_frame {
    const void* point;
    const char* source;
    const char* name;
    bool  tail;
    char flag;
    int line;
    uint64_t record_time;
    uint64_t call_time;
    uint64_t ret_time;
    uint64_t sub_cost;
    uint64_t real_cost;
};


struct call_state {
    int top;
    double leave_time;
    double enter_time;
    struct call_frame call_list[0];
};

struct call_info {
    struct call_state* cs;
    lua_State* co;
};

struct profile_context {
    struct {
        struct record_item* pool;
        size_t cap;
        size_t sz;
    } record_pool;
    struct imap_context* imap;

    bool start;
    struct imap_context* co_map;

    int ci_top;
    struct call_info ci_list[0];
};

static const char KEY = 'k';

static struct profile_context *
profile_create() {
    struct profile_context* context = (struct profile_context*)pmalloc(
        sizeof(struct profile_context) + sizeof(struct call_info)*MAX_CI_SIZE);
    
    context->start = false;
    context->imap = imap_create();
    context->co_map = imap_create();
    context->ci_top = 0;
    context->record_pool.pool = (struct record_item*)pmalloc(sizeof(struct record_item)*DEFAULT_POOL_ITEM_COUNT);
    context->record_pool.sz = DEFAULT_POOL_ITEM_COUNT;
    context->record_pool.cap = 0;
    return context;
}

static void
_ob_free_call_state(uint64_t key, void* value, void* ud) {
    pfree(value);
}

static void
profile_free(struct profile_context* context) {
    pfree(context->record_pool.pool);
    imap_free(context->imap);

    imap_dump(context->co_map, _ob_free_call_state, NULL);
    imap_free(context->co_map);
    pfree(context);
}

static void
_ob_reset_call_state(uint64_t key, void* value, void* ud) {
    struct call_state* cs = (struct call_state*)value;
    cs->top = 0;
}


static void
profile_reset(struct profile_context* context) {
    context->record_pool.cap = 0;
    context->ci_top = 0;
    imap_dump(context->co_map, _ob_reset_call_state, NULL);
    imap_free(context->imap);
    context->imap = imap_create();
}


static inline struct call_info *
push_callinfo(struct profile_context* context) {
    if(context->ci_top >= MAX_CI_SIZE) {
        assert(false);
    }
    return &context->ci_list[context->ci_top++];
}


static inline struct call_info *
pop_callinfo(struct profile_context* context) {
    if(context->ci_top<=0) {
        assert(false);
    }
    return &context->ci_list[--context->ci_top];
}


static struct call_state *
get_call_state(struct profile_context* context, lua_State* co, int* co_status) {
    int ci_top = context->ci_top;
    struct call_info* cur_co_info = NULL;
    struct call_info* pre_co_info = NULL;
    if(ci_top > 0) {
        cur_co_info = &context->ci_list[ci_top-1];
    }
    if(ci_top >= 2) {
        pre_co_info = &context->ci_list[ci_top-2];
    }
    if(cur_co_info && cur_co_info->co == co) {
        *co_status = 0;
        return cur_co_info->cs;
    }

    uint64_t key = (uint64_t)((uintptr_t)co);
    struct call_state* cs = imap_query(context->co_map, key);
    if(cs == NULL) {
        cs = (struct call_state*)pmalloc(sizeof(struct call_state) + sizeof(struct call_frame)*MAX_CALL_SIZE);
        cs->top = 0;
        cs->enter_time = 0.0;
        cs->leave_time = 0.0;
        imap_set(context->co_map, key, cs);
    }

    if(pre_co_info && cs == pre_co_info->cs) {  // pop co
        *co_status = -1;
    }else {  // push co
        struct call_info* ci = push_callinfo(context);
        ci->cs = cs;
        ci->co = co;
        *co_status = 1;
    }

    return cs;
}


static inline struct call_frame *
push_callframe(struct call_state* cs) {
    if(cs->top >= MAX_CALL_SIZE) {
        assert(false);
    }
    return &cs->call_list[cs->top++];
}

static inline struct call_frame *
pop_callframe(struct call_state* cs) {
    if(cs->top<=0) {
        assert(false);
    }
    return &cs->call_list[--cs->top];
}

static inline struct call_frame *
cur_callframe(struct call_state* cs) {
    if(cs->top<=0) {
        return NULL;
    }

    uint64_t idx = cs->top-1;
    return &cs->call_list[idx];
}

static struct record_item *
record_item_new(struct profile_context* context) {
    if(context->record_pool.cap >= context->record_pool.sz) {
        size_t new_sz = context->record_pool.sz * 2;
        struct record_item* new_pool = (struct record_item*)prealloc(context->record_pool.pool, new_sz*sizeof(struct record_item));
        assert(new_pool);
        context->record_pool.pool = new_pool;
        context->record_pool.sz = new_sz;
    }

    return &context->record_pool.pool[context->record_pool.cap++];
}


static void
record_item_add(struct profile_context* context, struct call_frame* frame) {
    uint64_t key = (uint64_t)((uintptr_t)frame->point);
    uint64_t record_pos = (uint64_t)((uintptr_t)imap_query(context->imap, key));
    struct record_item* item = NULL;

    if(record_pos==0) {
        item = record_item_new(context);
        size_t pos = context->record_pool.cap;
        item->point = frame->point;
        item->count = 0;
        item->flag = frame->flag;
        strncpy(item->source, frame->source, sizeof(item->source));
        item->source[MAX_SOURCE_LEN-1] = '\0'; // padding zero terimal
        strncpy(item->name, frame->name, sizeof(item->name));
        item->name[MAX_NAME_LEN-1] = '\0'; // padding zero terimal
        item->line = frame->line;
        item->all_cost = 0;
        item->ave_cost = 0.0;
        item->percent = 0.0;
        imap_set(context->imap, key, (void*)(pos));
    } else {
        item = get_item(context, record_pos-1);
    }

    item->count++;
    item->all_cost += frame->real_cost;
}



#ifdef WIN32
    #include <windows.h>
    // 定义纳秒常量
    #define NANOSEC 1000000000L
    // 获取当前时间，尽可能接近Linux的gettime()行为
    long long gettime() {
        LARGE_INTEGER freq, counter;
        static double freqToSec = 0.0;

        // 如果freqToSec尚未初始化，则初始化它
        if (freqToSec == 0.0) {
            QueryPerformanceFrequency(&freq);
            freqToSec = 1.0 / (double)freq.QuadPart;
        }

        // 获取当前计数值
        QueryPerformanceCounter(&counter);

        // 计算秒数和纳秒数
        long long sec = (long long)(counter.QuadPart * freqToSec);
        long long nsec = (long long)(((counter.QuadPart * freqToSec) - sec) * NANOSEC);

        return sec * NANOSEC + nsec;
    }

    static inline double
        realtime(uint64_t t) {
        return (double)t / NANOSEC;
    }
#else
    static inline uint64_t
    gettime() {
        struct timespec ti;
        // clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ti);
        // clock_gettime(CLOCK_MONOTONIC, &ti);  
        clock_gettime(CLOCK_REALTIME, &ti);  // would be faster

        long sec = ti.tv_sec & 0xffff;
        long nsec = ti.tv_nsec;

        return sec * NANOSEC + nsec;
    }

    static inline double
    realtime(uint64_t t) {
        return (double)t / NANOSEC;
    }
#endif


static inline struct profile_context *
_get_profile(lua_State* L) {
    lua_rawgetp(L, LUA_REGISTRYINDEX, (void *)&KEY);
    struct profile_context* addr = (struct profile_context*)lua_touserdata(L, -1);
    lua_pop(L, 1);
    return addr;
}


static void
_resolve_hook(lua_State* L, lua_Debug* arv) {
    uint64_t cur_time = gettime();
    struct profile_context* context = _get_profile(L);
    if(!context->start) {
        return;
    }

    int event = arv->event;
    lua_Debug ar;
    int ret = lua_getstack(L, 0, &ar);
    const void* point = NULL;
    const char* source = NULL;
    const char* name = NULL;
    char flag = 'L';
    int line = -1;
    if(!ret) {
        return;
    }

    int co_status = 0;
    struct call_state* cs = get_call_state(context, L, &co_status);
    double co_cost = 0.0;
    if(co_status == 1) {
        cs->enter_time = cur_time;
        if(cs->leave_time > 0.0) {
            co_cost = cs->enter_time - cs->leave_time;
            assert(co_cost>0.0);
        }

    }else if(co_status == -1) {
        struct call_info* ci = pop_callinfo(context);
        ci->cs->leave_time = cur_time;
        co_cost = ci->cs->leave_time - ci->cs->enter_time;
        assert(co_cost>0.0);
    }

    #ifdef OPEN_DEBUG
        printf("hook L:%p ci_count:%d name:%s source:%s:%d event:%d\n", L, context->ci_top, name, source, line, event);
    #endif
    if(event == LUA_HOOKCALL || event == LUA_HOOKTAILCALL) {
        #ifdef USE_EXPORT_NAME
            lua_getinfo(L, "nSlf", &ar);
            name = ar.name;
        #else
            lua_getinfo(L, "Slf", &ar);
        #endif
        point = lua_topointer(L, -1);
        line = ar.linedefined;
        source = ar.source;
        if (ar.what[0] == 'C' && event == LUA_HOOKCALL) {
            lua_Debug ar2;
            int i=0;
            do {
                i++;
                ret = lua_getstack(L, i, &ar2);
                flag = 'C';
                if(ret) {
                    lua_getinfo(L, "Sl", &ar2);
                    if(ar2.what[0] != 'C') {
                        line = ar2.currentline;
                        source = ar2.source;
                        break;
                    }
                }
            }while(ret);
        }

        struct call_frame* frame = push_callframe(cs);
        frame->point = point;
        frame->flag = flag;
        frame->tail = event == LUA_HOOKTAILCALL;
        frame->source = (source)?(source):("null");
        frame->name = (name)?(name):("null");
        frame->line = line;
        frame->record_time = cur_time;
        frame->sub_cost = 0;
        frame->call_time = gettime();

    }else if(event == LUA_HOOKRET) {
        int len = cs->top;
        if(len <= 0) {
            return;
        }
        bool tail_call = false;
        do {
            struct call_frame* cur_frame = pop_callframe(cs);
            cur_frame->sub_cost += co_cost;
            uint64_t total_cost = cur_time - cur_frame->call_time;
            uint64_t real_cost = total_cost - cur_frame->sub_cost;
            cur_frame->ret_time = cur_time;
            cur_frame->real_cost = real_cost;
            record_item_add(context, cur_frame);
            struct call_frame* pre_frame = cur_callframe(cs);
            if(pre_frame) {
                tail_call = cur_frame->tail;
                cur_time = gettime();
                uint64_t s = cur_time - cur_frame->record_time;
                pre_frame->sub_cost += s;
            }else {
                tail_call = false;
            }
        }while(tail_call);
    }
}


static int
_lstart(lua_State* L) {
    struct profile_context* context = _get_profile(L);
    context->start = true;
    lua_sethook(L, _resolve_hook, LUA_MASKCALL | LUA_MASKRET, 0);
    return 0;
}


static int
_lmark(lua_State* L) {
    struct profile_context* context = _get_profile(L);
    lua_State* co = lua_tothread(L, 1);
    if(co == NULL) {
        co = L;
    }
    if(context->start) {
        lua_sethook(co, _resolve_hook, LUA_MASKCALL | LUA_MASKRET, 0);
    }
    lua_pushboolean(L, context->start);
    return 1;
}

static int
_lunmark(lua_State* L) {
    lua_State* co = lua_tothread(L, 1);
    if(co == NULL) {
        co = L;
    }
    lua_sethook(co, NULL, 0, 0);
    return 0;
}


struct dump_arg {
    int stage;
    struct profile_context* context;
    double total;

    int cap;
    struct record_item** records;
};

static void
_observer(uint64_t key, void* value, void* ud) {
    struct dump_arg* args = (struct dump_arg*)ud;
    size_t pos = (size_t)((uintptr_t)value);
    struct record_item* item = get_item(args->context, pos-1);

    if(args->stage == 0) {
        args->total += realtime(item->all_cost);
        item->ave_cost = realtime(item->all_cost) / item->count;
    }else if(args->stage == 1) {
        item->percent = realtime(item->all_cost) / args->total;
        args->records[args->cap++] = item;
    }
}


static int
_compar(const void* v1, const void* v2) {
    struct record_item* a = *(struct record_item**)v1;
    struct record_item* b = *(struct record_item**)v2;
    signed long long f = b->all_cost - a->all_cost;
    return (f<0)?(-1):(1);
}


static void
_item2table(lua_State* L, struct record_item* v) {
    char s[2] = {0};
    lua_newtable(L);
    lua_pushlightuserdata(L, (void*)v->point);
    lua_setfield(L, -2, "point");

    lua_pushstring(L, v->name);
    lua_setfield(L, -2, "name");

    s[0] = v->flag;
    lua_pushstring(L, s);
    lua_setfield(L, -2, "flag");

    lua_pushstring(L, v->source);
    lua_setfield(L, -2, "source");

    lua_pushinteger(L, v->line);
    lua_setfield(L, -2, "line");

    lua_pushinteger(L, v->count);
    lua_setfield(L, -2, "count");

    lua_pushnumber(L, realtime(v->all_cost));
    lua_setfield(L, -2, "all_cost");

    lua_pushnumber(L, v->ave_cost);
    lua_setfield(L, -2, "ave_cost");

    lua_pushnumber(L, v->percent);
    lua_setfield(L, -2, "percent");
}


static void 
_ob_clear(uint64_t key, void* value, void* ud) {
    struct imap_context* co_map = (struct imap_context*)ud;
    struct call_state* cs = (struct call_state*)value;
    #ifdef OPEN_DEBUG
        int i;
        printf("---- lua_state:%llx ----\n", key);
        for(i=0; i<cs->top; i++) {
            struct call_frame* frame = &cs->call_list[i];
            printf("[%d] name:%s source:%s:%d\n", i, frame->name, frame->source, frame->line);
        }
    #endif
    imap_remove(co_map, key);
    pfree(cs);
}

static void
_clear_call_state(struct profile_context* context) {
    imap_dump(context->co_map, _ob_clear, context->co_map);
}

static void
dump_record_items(lua_State *L, struct profile_context* context) {
    if (!context) {
        context = _get_profile(L);
    }

    size_t sz = context->record_pool.cap;
    size_t count = (size_t)luaL_optinteger(L, 1, sz);
    count = (count > sz)?(sz):(count);

    struct dump_arg arg;
    arg.context = context;
    arg.stage = 0;
    arg.total = 0.0;
    arg.cap = 0;
    arg.records = (struct record_item**)pmalloc(sz*sizeof(struct record_item*));

    // calculate total and ave_cost
    imap_dump(context->imap, _observer, (void*)&arg);

    // calculate percent
    arg.stage = 1;
    imap_dump(context->imap, _observer, (void*)&arg);

    // sort record
    qsort((void*)arg.records, arg.cap, sizeof(struct record_item*), _compar);

    lua_newtable(L);
    int i=0;
    for(i=0; i<count; i++) {
        struct record_item* v = arg.records[i];
        _item2table(L, v);
        lua_seti(L, -2, i+1);
    }

    pfree(arg.records);
}

static int
_lstop(lua_State* L) {
    lua_sethook(L, NULL, 0, 0);
    struct profile_context* context = _get_profile(L);

    dump_record_items(L, context);

    _clear_call_state(context);

    context->start = false;
    // reset
    profile_reset(context);
    return 1;
}


static int
_ldump(lua_State* L) {
    dump_record_items(L, NULL);
    return 1;
}

static int
_linit(lua_State* L) {
    struct profile_context* context = _get_profile(L);
    if(context) {
        luaL_error(L, "profile context already initialized!");
    }

    context = profile_create();

    // init registry
    lua_pushlightuserdata(L, context);
    lua_rawsetp(L, LUA_REGISTRYINDEX, (void *)&KEY);
    return 0;
}

static int
_ldestory(lua_State* L) {
    struct profile_context* context = _get_profile(L);
    if(context) {
        profile_free(context);

        // reset registry
        lua_pushlightuserdata(L, (void *)&KEY);
        lua_pushnil(L);
        lua_settable(L, LUA_REGISTRYINDEX);
    }
    return 0;
}


LUALIB_API int
luaopen_lprofiler(lua_State* L) {
    luaL_checkversion(L);
     luaL_Reg l[] = {
        {"start", _lstart},
        {"stop", _lstop},
        {"mark", _lmark},
        {"unmark", _lunmark},
        {"init", _linit},
        {"destory", _ldestory},
        {"dump", _ldump},
        {NULL, NULL},
    };
    luaL_newlib(L, l);
    return 1;
}


