#pragma once

#include <thread>
#include <chrono>
#include <ctime>

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

	inline std::tm* localtime(std::time_t* t, std::tm* result)
	{
#ifdef WIN32
		localtime_s(result, t);
#else
		localtime_r(t, result);
#endif
		return result;
	}

	inline std::tm gmtime(const std::time_t& time_tt)
	{

#ifdef WIN32
		std::tm tm;
		gmtime_s(&tm, &time_tt);
#else
		std::tm tm;
		gmtime_r(&time_tt, &tm);
#endif
		return tm;
	}

	inline int timezone() {
		static int tz = 0;
		if (tz == 0) {
			auto t = std::time(nullptr);
			auto gm_tm = gmtime(t);
			std::tm local_tm;
			localtime(&t, &local_tm);
			auto diff = local_tm.tm_hour - gm_tm.tm_hour;
			if (diff < -12) {
				diff += 24;
			}else if (diff > 12) {
				diff -= 24;
			}
			tz = diff;
		}
		return tz;
	}

}
