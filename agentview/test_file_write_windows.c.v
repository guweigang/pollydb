module agentview

#include <windows.h>

fn C.GetLastError() u32

fn write_agentview_test_file_platform(path string, content string) ! {
	handle := C.CreateFileW(path.to_wide(), C.GENERIC_WRITE,
		C.FILE_SHARE_READ | C.FILE_SHARE_DELETE, unsafe { nil }, C.CREATE_ALWAYS,
		C.FILE_ATTRIBUTE_NORMAL, unsafe { nil })
	if handle == C.INVALID_HANDLE_VALUE || handle == unsafe { nil } {
		return error('failed to create AgentView test fixture `${path}`: ${C.GetLastError()}')
	}
	defer {
		C.CloseHandle(handle)
	}
	mut cursor := 0
	data := content.bytes()
	for cursor < data.len {
		remaining := data.len - cursor
		chunk_size := u32(remaining)
		mut written := u32(0)
		start := unsafe { &u8(voidptr(usize(data.data) + usize(cursor))) }
		if C.WriteFile(handle, start, chunk_size, &written, unsafe { nil }) == 0 {
			return error('failed to write AgentView test fixture `${path}`: ${C.GetLastError()}')
		}
		if written == 0 {
			return error('Windows AgentView test fixture write made no progress: `${path}`')
		}
		cursor += int(written)
	}
}
