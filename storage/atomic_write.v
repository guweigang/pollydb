module storage

import os
import rand
import time

// atomic_write_bytes durably stages data before replacing the destination.
// Besides avoiding torn metadata, the Windows staging implementation bypasses
// the CRT write path, which can report zero-byte writes on hosted runners.
fn atomic_write_bytes(path string, data []u8) ! {
	tmp_path := '${path}.tmp.${os.getpid()}.${time.now().unix_micro()}.${rand.uuid_v4()}'
	write_atomic_stage(tmp_path, data)!
	atomic_replace_file(tmp_path, path) or {
		os.rm(tmp_path) or {}
		return err
	}
}

fn write_atomic_stage(path string, data []u8) ! {
	$if windows {
		write_atomic_stage_windows(path, data)!
	} $else {
		mut tmp_file := os.open_file(path, 'wb', 0o666)!
		defer {
			tmp_file.close()
		}
		if data.len > 0 {
			written := tmp_file.write(data)!
			if written != data.len {
				return error('short metadata write: wrote ${written} of ${data.len} bytes')
			}
		}
		tmp_file.flush()
		$if darwin || linux {
			chunk_store_fsync_fd(tmp_file.fd)!
		}
	}
}
