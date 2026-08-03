module storage

import os
import time

#include <windows.h>

fn C.MoveFileExW(existing_file_name &u16, new_file_name &u16, flags u32) int
fn C.GetLastError() u32

const move_file_replace_existing = u32(0x1)
const move_file_write_through = u32(0x8)
const windows_error_file_not_found = u32(2)

fn atomic_replace_file(source string, destination string) ! {
	flags := move_file_replace_existing | move_file_write_through
	mut last_error := u32(0)
	for _ in 0 .. 200 {
		if C.MoveFileExW(source.to_wide(), destination.to_wide(), flags) != 0 {
			return
		}
		last_error = C.GetLastError()
		// Concurrent writers can race on a staged source name. If another
		// writer already consumed it and installed a destination, the replace
		// has reached a valid atomic outcome.
		if last_error == windows_error_file_not_found && os.exists(destination) {
			return
		}
		if last_error != 5 && last_error != 32 {
			break
		}
		time.sleep(2 * time.millisecond)
	}
	return error('atomic file replacement failed with Windows error ${last_error}')
}
