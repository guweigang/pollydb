module main

import net.http
import os
import pollylink
import storage

fn usage() string {
	return 'Usage:\n  pollylink-sidecar [storage_root] [default_branch] [addr]\n\nDefaults:\n  storage_root   current directory\n  default_branch repository default branch or main\n  addr           127.0.0.1:19191\n\nNotes:\n  The sidecar can host the root repository at storage_root and additional namespaced repositories under storage_root/<repo_name>.\n'
}

fn repository_meta_path(root_dir string) string {
	return os.join_path(root_dir, '.pollydb', 'repo.meta')
}

fn detect_default_branch(root_dir string) string {
	if os.exists(repository_meta_path(root_dir)) {
		repo := storage.Repository.open(repository_meta_path(root_dir)) or {
			return 'main'
		}
		return repo.default_branch
	}
	return 'main'
}

fn main() {
	args := if os.args.len > 1 && os.args[1] == '--' { os.args[2..] } else { os.args[1..] }
	if args.len > 0 && (args[0] == '-h' || args[0] == '--help' || args[0] == 'help') {
		println(usage())
		return
	}
	root_dir := if args.len > 0 { os.real_path(args[0]) } else { os.getwd() }
	default_branch := if args.len > 1 { args[1] } else { detect_default_branch(root_dir) }
	addr := if args.len > 2 { args[2] } else { '127.0.0.1:19191' }
	mut server := &http.Server{
		addr: addr
		handler: pollylink.SidecarHandler{
			root_dir: root_dir
			default_branch: default_branch
		}
	}
	server.listen_and_serve()
	if server.status() == .closed {
		eprintln('failed to start Polly-Link Sidecar')
	}
}
