module storage

import os
import time

$if windows {
	#flag -I @VMODROOT/storage/c
	#include "file_write_windows.h"

	fn C.pollytree_write_fd_at_end(fd int, buffer voidptr, count u32, last_error &u32) int
}

fn storage_file_write(mut file os.File, data []u8) !int {
	$if windows {
		mut cursor := 0
		mut retries := 0
		for cursor < data.len {
			remaining := data.len - cursor
			chunk_size := if remaining > 0x7fffffff { u32(0x7fffffff) } else { u32(remaining) }
			start := unsafe { voidptr(usize(data.data) + usize(cursor)) }
			mut last_error := u32(0)
			written := C.pollytree_write_fd_at_end(file.fd, start, chunk_size, &last_error)
			if written < 0 {
				return error('Windows storage WriteFile failed: ${last_error}')
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
