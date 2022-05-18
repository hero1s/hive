
#ifdef WIN32

#include "stack_back_trace.h"
#include <dbghelp.h>

StackBackTrace::StackBackTrace()
    : _hProcess(GetCurrentProcess())
    , _symInitialized(SymInitialize(_hProcess, NULL, TRUE))
{}

StackBackTrace::~StackBackTrace()
{
    if (_symInitialized)
    {
        SymCleanup(_hProcess);
    }
}

std::string StackBackTrace::build()
{
    void* symbol[sizeof(SYMBOL_INFO) + MAX_SYMBOL_NAME_LEN];
    reinterpret_cast<SYMBOL_INFO*>(symbol)->SizeOfStruct = sizeof(SYMBOL_INFO);
    reinterpret_cast<SYMBOL_INFO*>(symbol)->MaxNameLen = MAX_SYMBOL_NAME_LEN;

    std::string result;
    void* stack[MAX_FRAMES_TO_CAPTURE];
    const WORD frames = CaptureStackBackTrace(0, MAX_FRAMES_TO_CAPTURE, stack, NULL);
    for (WORD i = 0; i < frames; i++)
    {
        SymFromAddr(_hProcess, reinterpret_cast<DWORD64>(stack[i]), 0, reinterpret_cast<SYMBOL_INFO*>(symbol));

        char buf[1024];
        sprintf_s(buf, "%05d: %s - 0x%llx\n", frames - i - 1, reinterpret_cast<SYMBOL_INFO*>(symbol)->Name, reinterpret_cast<SYMBOL_INFO*>(symbol)->Address);
        result += buf;
    }

    return result;
}

#endif


