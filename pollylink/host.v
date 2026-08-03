module pollylink

import net.http
import storage

pub fn handle_sidecar_request(root_dir string, default_branch string, req http.Request) http.Response {
	return storage.handle_pollylink_sidecar_request(root_dir, default_branch, req)
}
