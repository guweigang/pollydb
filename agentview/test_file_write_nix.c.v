module agentview

import os

fn write_agentview_test_file_platform(path string, content string) ! {
	os.write_file(path, content)!
}
