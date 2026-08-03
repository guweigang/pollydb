module storage

#include <windows.h>

fn C.MoveFileExW(existing_file_name &u16, new_file_name &u16, flags u32) int
fn C.GetLastError() u32

const move_file_replace_existing = u32(0x1)
const move_file_write_through = u32(0x8)

fn atomic_replace_file(source string, destination string) ! {
	flags := move_file_replace_existing | move_file_write_through
	if C.MoveFileExW(source.to_wide(), destination.to_wide(), flags) == 0 {
		return error('atomic file replacement failed with Windows error ${C.GetLastError()}')
	}
}
