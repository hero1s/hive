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

    inline bool is_leap_year(uint64_t ts) {
        tm tm_early = gmtime(ts);
        auto year = tm_early.tm_year;
        if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) {
            return true;
        }
        return false;
    }

	//判断一个月有多少天
	inline int month_days(int year, int month) {
		int flag = 0;
		if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) {
			flag = 1; //是闰年
		}
		static int const month_normal[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
		static int const month_ruinian[12] = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
		return flag ? month_ruinian[month] : month_normal[month];
	}

    //获得时间相差天数
    inline int diff_day(uint64_t _early, uint64_t _late) {
        if (_early == 0 || _late == 0)
            return 0;
        tm tm_early = gmtime(_early);
        tm tm_late  = gmtime(_late);

        if (tm_early.tm_year > tm_late.tm_year)
            return 0;

        //同年同日
        if (tm_early.tm_year == tm_late.tm_year && tm_early.tm_yday == tm_late.tm_yday)
            return 0;

        //同年判断
        if (tm_early.tm_year == tm_late.tm_year) {
            if (tm_early.tm_yday >= tm_late.tm_yday)
                return 0;

            return (tm_late.tm_yday - tm_early.tm_yday);
        }

        int32_t iDay = 0;
        //不同年时
        if (tm_early.tm_year != tm_late.tm_year) {
            tm tm_temp = tm_early;

            //获取12月31日时间
            tm_temp.tm_mon = 11;
            tm_temp.tm_mday = 31;
            tm_temp.tm_yday = 0;
            uint64_t _temp = mktime(&tm_temp);
            tm_temp = gmtime(_temp);            
            iDay = tm_temp.tm_yday - tm_early.tm_yday;

            iDay += 1; //跨年+1

            //获得相差年天数
            for (int32_t i = tm_early.tm_year + 1; i < tm_late.tm_year; i++) {
                tm_temp.tm_year++;
                tm_temp.tm_yday = 0;
                _temp = mktime(&tm_temp);
                tm_temp = gmtime(_temp);
                iDay += tm_temp.tm_yday;
                iDay += 1; //跨年+1
            }
        }
        return (iDay + tm_late.tm_yday);
    }

    //获得时间相差周数
    inline int32_t diff_week(uint64_t _early, uint64_t _late) {
        if (_early == 0 || _late == 0)
            return 0;

        tm tm_early = gmtime(_early);
        tm tm_late  = gmtime(_late);

        if (tm_early.tm_year > tm_late.tm_year)
            return 0;

        //同年同日
        if (tm_early.tm_year == tm_late.tm_year && tm_early.tm_yday == tm_late.tm_yday)
            return 0;

        //计算两个日期的每一个周六相差多少天
        if (tm_early.tm_wday != 6)
            tm_early.tm_mday += (6 - tm_early.tm_wday);
        if (tm_late.tm_wday != 6)
            tm_late.tm_mday += (6 - tm_late.tm_wday);

        int32_t iDay = diff_day(mktime(&tm_early), mktime(&tm_late));

        int32_t iWeek = 0;
        if (iDay > 0)
            iWeek = iDay / 7; //肯定相差都是7的倍数因为都是周六

        return iWeek;
    }

    //获得时间相差月数
    inline int32_t diff_month(uint64_t _early, uint64_t _late)
    {
        if (_early == 0 || _late == 0)
            return 0;

        tm tm_early = gmtime(_early);
        tm tm_late  = gmtime(_late);

        if (tm_early.tm_year > tm_late.tm_year)
            return 0;

        //同年同月
        if (tm_early.tm_year == tm_late.tm_year && tm_early.tm_mon == tm_late.tm_mon)
            return 0;

        //同年判断
        if (tm_early.tm_year == tm_late.tm_year)
            return (tm_late.tm_mon - tm_early.tm_mon);

        int32_t iMon = 0;
        //不同年时
        if (tm_early.tm_year != tm_late.tm_year) {
            //计算相差年数
            iMon = (tm_late.tm_year - tm_early.tm_year) * 12;
            //再计算相差月数
            iMon += tm_late.tm_mon;
            if (iMon >= tm_early.tm_mon)
                iMon -= tm_early.tm_mon;
            else
                iMon = 0;
        }

        return iMon;
    }

    inline bool is_birthday(uint64_t _early, uint64_t _late) {
        tm tm_early = gmtime(_early);
        tm tm_late  = gmtime(_late);
        return tm_early.tm_mon == tm_late.tm_mon && tm_early.tm_mday == tm_late.tm_mday;
    }

}
