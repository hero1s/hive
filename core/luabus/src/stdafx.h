// stdafx.h : include file for standard system include files,
// or project specific include files that are used frequently, but
// are changed infrequently
//

#pragma once

#ifdef WIN32

// Modify the following defines if you have to target a platform prior to the ones specified below.
// Refer to MSDN for the latest info on corresponding values for different platforms.
#ifndef WINVER				// Allow use of features specific to Windows XP or later.
#define WINVER 0x0603		// Change this to the appropriate value to target other versions of Windows.
#endif

#ifndef _WIN32_WINNT		// Allow use of features specific to Windows XP or later.                   
#define _WIN32_WINNT 0x0603	// Change this to the appropriate value to target other versions of Windows.
#endif						

#ifndef _WIN32_WINDOWS		// Allow use of features specific to Windows 98 or later.
#define _WIN32_WINDOWS 0x0510 // Change this to the appropriate value to target Windows Me or later.
#endif

#ifndef _WIN32_IE			// Allow use of features specific to IE 6.0 or later.
#define _WIN32_IE 0x0A00	// Change this to the appropriate value to target other versions of IE.
#endif

#define WIN32_LEAN_AND_MEAN		// Exclude rarely-used stuff from Windows headers
// Windows Header Files:

#include <Winsock2.h>
#include <Ws2tcpip.h>
#include <mswsock.h>
#include <windows.h>

#endif

// TODO: reference additional headers your program requires here
#pragma warning(disable: 4996)
#pragma warning(disable: 4311)
#pragma warning(disable: 4312)
#pragma warning(disable: 4244)
#pragma warning(disable: 4267)
#pragma warning(disable: 4819)
#pragma warning(disable: 4313)
#pragma warning(disable: 4251)

#include <string>
#include <exception>
#include <assert.h>

#ifdef __linux
#include <sys/epoll.h>
#endif
#ifdef __APPLE__
#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#endif
#if defined(__linux) || defined(__APPLE__)
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#endif

#define LUA_LIB

#include <iostream>
