module storage

import time

#include <windows.h>

fn C.FlushFileBuffers(file voidptr) int
fn C.CloseHandle(object voidptr) int
fn C.GetLastError() u32

fn write_atomic_stage_windows(path string, data []u8) ! {
	mut handle := voidptr(0)
	mut last_error := u32(0)
	for attempt in 0 .. 200 {
		handle = C.CreateFileW(path.to_wide(), C.GENERIC_WRITE, 0, unsafe { nil }, C.CREATE_ALWAYS,
			C.FILE_ATTRIBUTE_NORMAL, unsafe { nil })
		if handle != C.INVALID_HANDLE_VALUE && handle != unsafe { nil } {
			break
		}
		last_error = C.GetLastError()
		if (last_error != 5 && last_error != 32) || attempt == 199 {
			break
		}
		time.sleep(2 * time.millisecond)
	}
	if handle == C.INVALID_HANDLE_VALUE || handle == unsafe { nil } {
		return error('failed to create Windows staging file: ${last_error}')
	}
	defer {
		C.CloseHandle(handle)
	}
	mut cursor := 0
	for cursor < data.len {
		remaining := data.len - cursor
		chunk_size := u32(remaining)
		mut written := u32(0)
		start := unsafe { &u8(voidptr(usize(data.data) + usize(cursor))) }
		if !C.WriteFile(handle, start, chunk_size, &written, unsafe { nil }) {
			return error('failed to write Windows staging file: ${C.GetLastError()}')
		}
		if written == 0 {
			return error('Windows staging write made no progress')
		}
		cursor += int(written)
	}
	if C.FlushFileBuffers(handle) == 0 {
		return error('failed to flush Windows staging file: ${C.GetLastError()}')
	}
}
