module storage

import os
import rand

// atomic_write_bytes durably stages data before replacing the destination.
// Besides avoiding torn metadata, the Windows staging implementation bypasses
// the CRT write path, which can report zero-byte writes on hosted runners.
fn atomic_write_bytes(path string, data []u8) ! {
	os.mkdir_all(os.dir(path))!
	tmp_path := atomic_stage_path(path)
	write_atomic_stage(tmp_path, data)!
	atomic_replace_file(tmp_path, path) or {
		os.rm(tmp_path) or {}
		return err
	}
}

fn atomic_stage_path(path string) string {
	token := rand.uuid_v4().replace('-', '')
	return os.join_path(os.dir(path), '.pt-${os.getpid()}-${token[..12]}')
}

fn write_atomic_stage(path string, data []u8) ! {
	os.mkdir_all(os.dir(path))!
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
