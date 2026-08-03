module storage

import os

fn storage_file_write(mut file os.File, data []u8) !int {
	$if windows {
		return storage_file_write_windows(file.fd, data)
	} $else {
		return file.write(data)
	}
}
