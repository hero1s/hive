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
		return duration_cast<seconds>(system_clock::now().time_since_epoch()).count() + offset_;
	}

	inline uint64_t now_ms() {
		return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count() + offset_*1000;
	}

	inline uint64_t steady() {
		return duration_cast<seconds>(steady_clock::now().time_since_epoch()).count();
	}

	inline uint64_t steady_ms() {
		return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
	}

	inline void sleep(uint64_t ms) {
		std::this_thread::sleep_for(std::chrono::milliseconds(ms));
	}

	inline std::time_t make_time(int year, int month, int day, int hour, int min, int sec) {
		std::tm _tm;
		_tm.tm_year = (year - 1900);
		_tm.tm_mon = (month - 1);
		_tm.tm_mday = day;
		_tm.tm_hour = hour;
		_tm.tm_min = min;
		_tm.tm_sec = sec;
		_tm.tm_isdst = 0;
		return mktime(&_tm);
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

    inline bool is_leap_year(int year) {
        if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) {
            return true;
        }
        return false;
    }

    //获得今日开始时间
    inline uint64_t day_begin_time(uint64_t ts) {
        auto _tm = gmtime(ts);
        _tm.tm_hour = 0;
        _tm.tm_min = 0;
        _tm.tm_sec = 0;
        return mktime(&_tm);
    }

	//判断一个月有多少天
	inline int month_days(uint64_t ts) {
        tm tm_ts = gmtime(ts);
		static int const month_normal[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
		static int const month_ruinian[12] = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
		return is_leap_year(tm_ts.tm_year) ? month_ruinian[tm_ts.tm_mon] : month_normal[tm_ts.tm_mon];
	}

    inline int local_day(uint64_t ts) {
        tm tm_ts = gmtime(ts);
        auto days_before_year = [](int year) {
            year--;
            return year * 365 + year / 4 - year / 100 + year / 400;
        };
        auto days_before_month = [](int year, int month) {
            static int const DAYS_BEFORE_MONTH[] = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };
            if (month > 1 && is_leap_year(year)) {
                return DAYS_BEFORE_MONTH[month] + 1;
            }
            return DAYS_BEFORE_MONTH[month];
        };
        return days_before_year(tm_ts.tm_year) + days_before_month(tm_ts.tm_year, tm_ts.tm_mon) + tm_ts.tm_mday;
    }

    //获得时间相差天数
    inline int diff_day(uint64_t _early, uint64_t _late) {
        auto de = local_day(_early);
        auto dl = local_day(_late);
        return dl - de;
    }

    //获得时间相差周数
    inline int diff_week(uint64_t _early, uint64_t _late) {
        tm tm_early = gmtime(_early);
        tm tm_late  = gmtime(_late);
        //同年同日
        if (tm_early.tm_year == tm_late.tm_year && tm_early.tm_yday == tm_late.tm_yday)
            return 0;

        //计算两个日期的每一个周六相差多少天
        if (tm_early.tm_wday != 6)
            tm_early.tm_mday += (6 - tm_early.tm_wday);
        if (tm_late.tm_wday != 6)
            tm_late.tm_mday += (6 - tm_late.tm_wday);

        auto iDay = diff_day(mktime(&tm_early), mktime(&tm_late));
        return iDay / 7; //肯定相差都是7的倍数因为都是周六
    }

    //获得时间相差月数
    inline int diff_month(uint64_t _early, uint64_t _late) {
        tm tm_early = gmtime(_early);
        tm tm_late  = gmtime(_late);

        //同年同月
        if (tm_early.tm_year == tm_late.tm_year && tm_early.tm_mon == tm_late.tm_mon)
            return 0;

        //同年判断
        if (tm_early.tm_year == tm_late.tm_year)
            return (tm_late.tm_mon - tm_early.tm_mon);

        int iMon = 0;
        //不同年时
        if (tm_early.tm_year != tm_late.tm_year) {
            //计算相差年数
            iMon = (tm_late.tm_year - tm_early.tm_year) * 12;
            //再计算相差月数
            iMon += tm_late.tm_mon;
            iMon -= tm_early.tm_mon;
        }
        return iMon;
    }

    inline bool is_birthday(uint64_t _early, uint64_t _late) {
        tm tm_early = gmtime(_early);
        tm tm_late  = gmtime(_late);
        return tm_early.tm_mon == tm_late.tm_mon && tm_early.tm_mday == tm_late.tm_mday;
    }

}
