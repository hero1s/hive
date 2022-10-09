#pragma once

#ifdef WIN32

#include <windows.h>
#include <string>

class StackBackTrace
{
public:
	StackBackTrace();
	virtual ~StackBackTrace();

	std::string build();

private:
	static const int MAX_FRAMES_TO_CAPTURE = 256;
	static const int MAX_SYMBOL_NAME_LEN = MAX_PATH;

	const HANDLE _hProcess;
	const bool _symInitialized;
};

#endif

