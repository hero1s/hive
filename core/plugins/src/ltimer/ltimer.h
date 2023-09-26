#pragma once

#include <thread>
#include <chrono>

using namespace std::chrono;

namespace ltimer {
	inline static std::time_t offset_ = 0;

	inline void offset(std::time_t v) {
		offset_ = v;
	}

	inline uint64_t now() {
		system_clock::duration dur = system_clock::now().time_since_epoch();
		return duration_cast<seconds>(dur).count() + offset_;
	}

	inline uint64_t now_ms() {
		system_clock::duration dur = system_clock::now().time_since_epoch();
		return duration_cast<milliseconds>(dur).count() + offset_*1000;
	}

	inline uint64_t steady() {
		steady_clock::duration dur = steady_clock::now().time_since_epoch();
		return duration_cast<seconds>(dur).count();
	}

	inline uint64_t steady_ms() {
		steady_clock::duration dur = steady_clock::now().time_since_epoch();
		return duration_cast<milliseconds>(dur).count();
	}

	inline void sleep(uint64_t ms) {
		std::this_thread::sleep_for(std::chrono::milliseconds(ms));
	}

}
