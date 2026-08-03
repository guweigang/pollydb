module storage

import os

fn atomic_replace_file(source string, destination string) ! {
	os.mv(source, destination)!
}
