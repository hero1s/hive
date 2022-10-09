#include <list>
#include "ltimer.h"
#include "croncpp.h"
#include "lua_kit.h"

constexpr int TIME_NEAR_SHIFT = 8;
constexpr int TIME_LEVEL_SHIFT = 6;
constexpr int TIME_NEAR = (1 << TIME_NEAR_SHIFT);
constexpr int TIME_LEVEL = (1 << TIME_LEVEL_SHIFT);
constexpr int TIME_NEAR_MASK = (TIME_NEAR - 1);
constexpr int TIME_LEVEL_MASK = (TIME_LEVEL - 1);

namespace ltimer {

	struct timer_node {
		size_t expire;
		uint64_t timer_id;
	};

	using timer_list = std::list<timer_node>;
	using integer_vector = std::vector<uint64_t>;

	class lua_timer {
	public:
		integer_vector update(size_t elapse);
		void insert(uint64_t timer_id, size_t escape);

	protected:
		void shift();
		void add_node(timer_node&& node);
		void execute(integer_vector& timers);
		void move_list(uint32_t level, uint32_t idx);

	protected:
		size_t time = 0;
		timer_list near[TIME_NEAR];
		timer_list t[4][TIME_LEVEL];
	};

	void lua_timer::add_node(timer_node&& node) {
		size_t expire = node.expire;
		if ((expire | TIME_NEAR_MASK) == (time | TIME_NEAR_MASK)) {
			near[expire & TIME_NEAR_MASK].emplace_back(node);
			return;
		}
		uint32_t i;
		uint32_t mask = TIME_NEAR << TIME_LEVEL_SHIFT;
		for (i = 0; i < 3; i++) {
			if ((expire | (mask - 1)) == (time | (mask - 1))) {
				break;
			}
			mask <<= TIME_LEVEL_SHIFT;
		}
		t[i][((expire >> (TIME_NEAR_SHIFT + i * TIME_LEVEL_SHIFT)) & TIME_LEVEL_MASK)].emplace_back(node);
	}

	void lua_timer::insert(uint64_t timer_id, size_t escape) {
		timer_node node{ time + escape, timer_id };
		add_node(std::move(node));
	}

	void lua_timer::move_list(uint32_t level, uint32_t idx) {
		timer_list& list = t[level][idx];
		for (auto node : list) {
			add_node(std::move(node));
		}
		list.clear();
	}

	void lua_timer::shift() {
		size_t ct = ++time;
		if (ct == 0) {
			move_list(3, 0);
			return;
		}
		uint32_t i = 0;
		int mask = TIME_NEAR;
		size_t time = ct >> TIME_NEAR_SHIFT;
		while ((ct & (mask - 1)) == 0) {
			uint32_t idx = time & TIME_LEVEL_MASK;
			if (idx != 0) {
				move_list(i, idx);
				break;
			}
			mask <<= TIME_LEVEL_SHIFT;
			time >>= TIME_LEVEL_SHIFT;
			++i;
		}
	}

	void lua_timer::execute(integer_vector& timers) {
		uint32_t idx = time & TIME_NEAR_MASK;
		for (auto node : near[idx]) {
			timers.emplace_back(node.timer_id);
		}
		near[idx].clear();
	}

	integer_vector lua_timer::update(size_t elapse) {
		integer_vector timers;
		execute(timers);
		for (size_t i = 0; i < elapse; i++) {
			shift();
			execute(timers);
		}
		return timers;
	}

	luakit::variadic_results cron_next(lua_State* L, std::string cex) {
		luakit::kit_state kit_state(L);
		try {
			auto result = cron::cron_next(cron::make_cron(cex), (time_t)now());
			std::tm result_tm;
			cron::utils::time_to_tm(&result, &result_tm);
			return kit_state.as_return(result, cron::utils::to_string(result_tm));
		}
		catch (const std::exception& e) {
			return kit_state.as_return(-1, e.what());
		}
	}

	luakit::lua_table open_ltimer(lua_State* L) {
		luakit::kit_state kit_state(L);
		auto luatimer = kit_state.new_table();
		kit_state.new_class<lua_timer>("insert", &lua_timer::insert, "update", &lua_timer::update);
		luatimer.set_function("new", []() { return new lua_timer(); });
		luatimer.set_function("now", []() { return now(); });
		luatimer.set_function("now_ms", []() { return now_ms(); });
		luatimer.set_function("clock", []() { return steady(); });
		luatimer.set_function("clock_ms", []() { return steady_ms(); });
		luatimer.set_function("sleep", [](uint64_t ms) { return sleep(ms); });
		luatimer.set_function("cron_next", cron_next);
		luatimer.set_function("time", [](lua_State* L) {
			luakit::kit_state kit_state(L);
			return kit_state.as_return(now_ms(), steady_ms());
			});
		return luatimer;
	}
}

extern "C" {
	LUALIB_API int luaopen_ltimer(lua_State* L) {
		return ltimer::open_ltimer(L).push_stack();
	}
}
