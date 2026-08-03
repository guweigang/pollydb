module storage

import os
import rand
import time

// atomic_write_bytes durably stages data before replacing the destination.
// Besides avoiding torn metadata, using os.File here avoids the Windows CRT
// direct-write path used by os.write_file, which can occasionally report a
// zero-byte write on hosted runners.
fn atomic_write_bytes(path string, data []u8) ! {
	tmp_path := '${path}.tmp.${os.getpid()}.${time.now().unix_micro()}.${rand.u64()}'
	mut tmp_file := os.open_file(tmp_path, 'wb', 0o666)!
	mut tmp_file_open := true
	defer {
		if tmp_file_open {
			tmp_file.close()
		}
	}
	if data.len > 0 {
		written := tmp_file.write(data)!
		if written != data.len {
			return error('short metadata write: wrote ${written} of ${data.len} bytes')
		}
	}
	tmp_file.flush()
	$if darwin || linux || windows {
		chunk_store_fsync_fd(tmp_file.fd)!
	}
	tmp_file.close()
	tmp_file_open = false
	atomic_replace_file(tmp_path, path) or {
		os.rm(tmp_path) or {}
		return err
	}
}
