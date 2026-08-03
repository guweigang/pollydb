module storage

#include <io.h>
#include <windows.h>

fn C._get_osfhandle(fd int) isize
fn C.GetLastError() u32

fn storage_file_write_windows(fd int, data []u8) !int {
	handle_value := C._get_osfhandle(fd)
	if handle_value == -1 {
		return error('failed to resolve Windows file handle')
	}
	handle := voidptr(handle_value)
	mut cursor := 0
	for cursor < data.len {
		remaining := data.len - cursor
		mut written := u32(0)
		start := unsafe { &u8(voidptr(usize(data.data) + usize(cursor))) }
		if !C.WriteFile(handle, start, u32(remaining), &written, unsafe { nil }) {
			return error('failed to write Windows storage file: ${C.GetLastError()}')
		}
		if written == 0 {
			return error('Windows storage write made no progress')
		}
		cursor += int(written)
	}
	return cursor
}
