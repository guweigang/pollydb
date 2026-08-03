module storage

import time

#include <windows.h>

fn C.MoveFileExW(existing_file_name &u16, new_file_name &u16, flags u32) int
fn C.GetLastError() u32

const move_file_replace_existing = u32(0x1)
const move_file_write_through = u32(0x8)

fn atomic_replace_file(source string, destination string) ! {
	flags := move_file_replace_existing | move_file_write_through
	mut last_error := u32(0)
	for _ in 0 .. 200 {
		if C.MoveFileExW(source.to_wide(), destination.to_wide(), flags) != 0 {
			return
		}
		last_error = C.GetLastError()
		if last_error != 5 && last_error != 32 {
			break
		}
		time.sleep(2 * time.millisecond)
	}
	return error('atomic file replacement failed with Windows error ${last_error}')
}
