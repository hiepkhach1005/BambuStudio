// iOS SDK has no <libproc.h>. Only what libslic3r/utils.cpp uses: the path of the current process.
#pragma once
#include <mach-o/dyld.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#define PROC_PIDPATHINFO_MAXSIZE 4096
static inline int proc_pidpath(int pid, void *buffer, uint32_t size)
{
    if (pid != getpid()) return 0; // other processes are not visible in the sandbox
    if (_NSGetExecutablePath((char *) buffer, &size) != 0) return 0;
    return (int) strlen((const char *) buffer);
}
