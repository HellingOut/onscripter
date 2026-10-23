#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <execinfo.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#include "ONScripter.h"
#include "version.h"

extern ONScripter ons;

static char crash_log_path[PATH_MAX];
static volatile sig_atomic_t in_crash = 0;

static void makeDirectory(const char* path)
{
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "%s", path);

    for (char* p = tmp + 1; *p; p++) {
        if (*p != '/') continue;
        *p = '\0';
        mkdir(tmp, 0755);
        *p = '/';
    }
    mkdir(tmp, 0755);
}

static void writeAll(int fd, const char* data, size_t length)
{
    while (length > 0) {
        ssize_t written = write(fd, data, length);
        if (written <= 0) return;
        data += written;
        length -= written;
    }
}

static const char* signalName(int sig)
{
    switch (sig) {
    case SIGSEGV: return "SIGSEGV";
    case SIGBUS: return "SIGBUS";
    case SIGILL: return "SIGILL";
    case SIGFPE: return "SIGFPE";
    case SIGABRT: return "SIGABRT";
    case SIGTRAP: return "SIGTRAP";
    default: return "UNKNOWN";
    }
}

static const char* encodingName(int code)
{
    switch (code) {
    case Encoding::CODE_CP932: return "CP932";
    case Encoding::CODE_UTF8: return "UTF-8";
    case Encoding::CODE_CP1251: return "CP1251";
    default: return "UNKNOWN";
    }
}

static void writeCrashHeader(int fd, const char* kind, int sig)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);

    const char* label = ons.getCurrentLabelName();
    if (!label || !*label) label = "(none)";
    const char* command = ons.getCurrentCommand();
    if (!command) command = "";

    char buffer[4096];
    int length = snprintf(buffer, sizeof(buffer),
                          "\n=== ONScripter %s ===\n"
                          "version: %s (%d.%02d)\n"
                          "time: %ld.%06ld\n"
                          "signal: %s (%d)\n"
                          "label: %s\n"
                          "line: %d\n"
                          "command: %s\n"
                          "screen: %dx%d\n"
                          "encoding: %s (%d)\n",
                          kind,
                          ONS_VERSION, NSC_VERSION / 100, NSC_VERSION % 100,
                          (long)tv.tv_sec, (long)tv.tv_usec,
                          signalName(sig), sig,
                          label, ons.getCurrentLineNumber(), command,
                          ons.getWidth(), ons.getHeight(),
                          encodingName(ons.getScriptEncoding()), ons.getScriptEncoding());
    if (length > 0) writeAll(fd, buffer, (size_t)length);

    writeAll(fd, "backtrace:\n", 11);

    void* frames[64];
    int count = backtrace(frames, 64);
    for (int i = 0; i < count; i++) {
        Dl_info info;
        if (dladdr(frames[i], &info) && info.dli_sname) {
            length = snprintf(buffer, sizeof(buffer), "  #%02d %p %s + %ld (%s)\n",
                              i, frames[i], info.dli_sname,
                              (long)((uintptr_t)frames[i] - (uintptr_t)info.dli_saddr),
                              info.dli_fname ? info.dli_fname : "");
        }
        else {
            length = snprintf(buffer, sizeof(buffer), "  #%02d %p\n", i, frames[i]);
        }
        if (length > 0) writeAll(fd, buffer, (size_t)length);
    }
}

static void crashSignalHandler(int sig)
{
    if (in_crash) {
        _exit(128 + sig);
    }
    in_crash = 1;

    int fd = open(crash_log_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        writeCrashHeader(fd, "CRASH", sig);
        fsync(fd);
        close(fd);
    }

    signal(sig, SIG_DFL);
    raise(sig);
    _exit(128 + sig);
}

static void logException(NSException* exception)
{
    int fd = open(crash_log_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;

    writeCrashHeader(fd, "UNCAUGHT EXCEPTION", 0);

    char buffer[2048];
    const char* name = [[exception name] UTF8String];
    const char* reason = [[exception reason] UTF8String];
    int length = snprintf(buffer, sizeof(buffer),
                          "exception: %s\nreason: %s\n",
                          name ? name : "",
                          reason ? reason : "");
    if (length > 0) writeAll(fd, buffer, (size_t)length);

    fsync(fd);
    close(fd);
}

static void exceptionHandler(NSException* exception)
{
    logException(exception);
}

extern "C" void installCrashLogger(void)
{
    const char* home = getenv("HOME");
    if (!home || !*home) home = "/var/mobile";

    char directory[PATH_MAX];
    snprintf(directory, sizeof(directory), "%s/Documents/ONS", home);
    makeDirectory(directory);
    snprintf(crash_log_path, sizeof(crash_log_path), "%s/crash.log", directory);

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = crashSignalHandler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESETHAND | SA_NODEFER;

    sigaction(SIGSEGV, &action, NULL);
    sigaction(SIGBUS, &action, NULL);
    sigaction(SIGILL, &action, NULL);
    sigaction(SIGFPE, &action, NULL);
    sigaction(SIGABRT, &action, NULL);

    NSSetUncaughtExceptionHandler(&exceptionHandler);
}
