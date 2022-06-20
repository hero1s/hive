#include <stdio.h>
#include <locale>
#include "hive.h"
#include "exception/stack_back_trace.h"

#ifdef WIN32
#define tzset _tzset
#endif

int main(int argc, const char* argv[])
{
    tzset();
    setlocale(LC_ALL, "");

    if (argc < 2)
    {
        std::cout << "--(hive_run program_entry.lua ...)--" << std::endl;
        return 0;
    }

    g_app = new hive_app();
    g_app->setup(argc, argv);
    delete g_app;
    return 0;
}


#ifdef WIN32
#pragma once
#include <Windows.h>
#include <imagehlp.h>
#include <tchar.h>
#pragma comment(lib,"DbgHelp.lib")

class CMiniDump
{
public:
	CMiniDump(void);
	virtual ~CMiniDump(void);

protected:
	static BOOL GetModulePath(LPTSTR lpBuf, DWORD dwBufSize);
	static LONG WINAPI MyUnhandledExceptionFilter(EXCEPTION_POINTERS* ExceptionInfo);
};


CMiniDump::CMiniDump(void)
{
	SetUnhandledExceptionFilter(&CMiniDump::MyUnhandledExceptionFilter);
}


CMiniDump::~CMiniDump(void)
{
}

LONG WINAPI CMiniDump::MyUnhandledExceptionFilter(EXCEPTION_POINTERS* ExceptionInfo)
{
	TCHAR sModulePath[MAX_PATH] = { 0 };
	GetModulePath(sModulePath, MAX_PATH);

	TCHAR sFileName[MAX_PATH] = { 0 };
	SYSTEMTIME	systime = { 0 };
	GetLocalTime(&systime);
	_stprintf_s(sFileName, _T("%04d%02d%02d-%02d%02d%02d.dmp"),
		systime.wYear, systime.wMonth, systime.wDay, systime.wHour, systime.wMinute, systime.wSecond);

	_tcscat_s(sModulePath, sFileName);
	HANDLE lhDumpFile = CreateFile(sModulePath, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
	MINIDUMP_EXCEPTION_INFORMATION loExceptionInfo;
	loExceptionInfo.ExceptionPointers = ExceptionInfo;
	loExceptionInfo.ThreadId = GetCurrentThreadId();
	loExceptionInfo.ClientPointers = FALSE;
	MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), lhDumpFile, MiniDumpNormal, &loExceptionInfo, NULL, NULL);
	CloseHandle(lhDumpFile);
	StackBackTrace stackBackTrace;
	LOG_ERROR(g_app->get_logger()) << stackBackTrace.build() << " \n";
	g_app->get_logger()->stop();
	return EXCEPTION_EXECUTE_HANDLER;
}

BOOL CMiniDump::GetModulePath(LPTSTR lpBuf, DWORD dwBufSize)
{
    TCHAR sModuleName[MAX_PATH] = { 0 };
    GetModuleFileName(NULL, sModuleName, MAX_PATH);
    TCHAR* pChar = _tcsrchr(sModuleName, _T('\\'));
    if (NULL != pChar)
    {
        size_t iPos = pChar - sModuleName;
        sModuleName[iPos + 1] = _T('\0');
        _tcscpy_s(lpBuf, dwBufSize, sModuleName);
        return TRUE;
    }
    return FALSE;
}

CMiniDump g_minidump;
#endif