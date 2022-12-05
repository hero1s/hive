#pragma once

#include <thread> //std::thread
#include <string_view> //std::string_view

#ifdef WIN32
#include "windows.h" //Win NT defines
#include "processthreadsapi.h" //SetTrheadDescription()
#include <cstdlib> //std::mbstowcs
#include <vector> //std::vector<wchar_t>
#else
#include <pthread.h>
#endif

namespace utility
{
	inline void set_thread_name(std::thread& thread, std::string_view thread_name)
	{
#ifdef WIN32
		std::vector<wchar_t> wide_char_string_data(thread_name.size() + 1);
		std::mbstowcs(wide_char_string_data.data(), thread_name.data(), thread_name.size());
		SetThreadDescription(thread.native_handle(), wide_char_string_data.data());
#else
		pthread_setname_np(thread.native_handle(), thread_name.data());
#endif
	}
}


