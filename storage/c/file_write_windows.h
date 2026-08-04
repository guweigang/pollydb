#ifndef POLLYTREE_FILE_WRITE_WINDOWS_H
#define POLLYTREE_FILE_WRITE_WINDOWS_H

#include <io.h>
#include <windows.h>

static int pollytree_write_fd_at_end(int fd, const void *buffer, unsigned int count,
                                     unsigned long *last_error) {
    const intptr_t raw_handle = _get_osfhandle(fd);
    if (raw_handle == -1) {
        *last_error = ERROR_INVALID_HANDLE;
        return -1;
    }

    const HANDLE handle = (HANDLE)raw_handle;
    LARGE_INTEGER zero;
    zero.QuadPart = 0;
    if (!SetFilePointerEx(handle, zero, NULL, FILE_END)) {
        *last_error = GetLastError();
        return -1;
    }

    DWORD written = 0;
    if (!WriteFile(handle, buffer, (DWORD)count, &written, NULL)) {
        *last_error = GetLastError();
        return -1;
    }
    return (int)written;
}

#endif
