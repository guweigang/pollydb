module storage

import os
import time

$if windows {
	#include <errno.h>
	#include <io.h>

	fn C._write(fd int, buffer voidptr, count u32) int
}

fn storage_file_write(mut file os.File, data []u8) !int {
	$if windows {
		mut cursor := 0
		mut retries := 0
		for cursor < data.len {
			remaining := data.len - cursor
			chunk_size := if remaining > int(u32(~u32(0))) { u32(~u32(0)) } else { u32(remaining) }
			start := unsafe { voidptr(usize(data.data) + usize(cursor)) }
			C.errno = 0
			written := C._write(file.fd, start, chunk_size)
			if written < 0 {
				cerror := int(C.errno)
				if cerror == C.EINTR && retries < 200 {
					retries++
					continue
				}
				return error('Windows storage _write failed: errno ${cerror}')
			}
			if written == 0 {
				if retries >= 200 {
					return error('Windows storage write made no progress')
				}
				retries++
				time.sleep(2 * time.millisecond)
				continue
			}
			cursor += written
		}
		return cursor
	} $else {
		return file.write(data)
	}
}
