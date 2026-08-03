module storage

import os

fn storage_file_write(mut file os.File, data []u8) !int {
	$if windows {
		// The CRT's append flag is not applied when writing through the native
		// handle, so position the shared handle explicitly before WriteFile.
		file.seek(0, .end)!
		return storage_file_write_windows(file.fd, data)
	} $else {
		return file.write(data)
	}
}
