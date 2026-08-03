module storage

import os
import time

fn storage_file_write(mut file os.File, data []u8) !int {
	$if windows {
		mut cursor := 0
		mut retries := 0
		for cursor < data.len {
			written := file.write(data[cursor..]) or {
				if err.msg() == '0 bytes written' && retries < 200 {
					retries++
					time.sleep(2 * time.millisecond)
					continue
				}
				return err
			}
			if written == 0 {
				if retries >= 200 {
					return error('Windows storage write made no progress')
				}
				retries++
				time.sleep(2 * time.millisecond)
				continue
			}
			cursor += written
		}
		return cursor
	} $else {
		return file.write(data)
	}
}
