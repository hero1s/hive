#pragma once
#ifndef __MIMALLOC_EX_H__
#define __MIMALLOC_EX_H__

#include <stdlib.h>
#include <string.h>
#ifndef __APPLE__
#include <malloc.h>
#endif
#ifdef __APPLE__
#include <unistd.h>
#endif

#include "mimalloc-override.h"

#endif
