module memory

#flag -I @VMODROOT/thirdparty/native/include
#flag darwin -L @VMODROOT/thirdparty/native/lib
#flag darwin -lusearch_c
#flag darwin -Wl,-rpath,@VMODROOT/thirdparty/native/lib
#flag linux -L @VMODROOT/thirdparty/native/lib
#flag linux -lusearch_c
#flag linux -Wl,-rpath,@VMODROOT/thirdparty/native/lib
#flag linux -lm
#flag windows @VMODROOT/thirdparty/native/lib/libusearch_static_c.lib
#include "usearch.h"

struct C.usearch_init_options_t {
	metric_kind      int
	metric           voidptr
	quantization     int
	dimensions       usize
	connectivity     usize
	expansion_add    usize
	expansion_search usize
	multi            bool
}

fn C.usearch_init(options &C.usearch_init_options_t, err &&char) voidptr
fn C.usearch_free(index voidptr, err &&char)
fn C.usearch_reserve(index voidptr, capacity usize, err &&char)
fn C.usearch_contains(index voidptr, key u64, err &&char) bool
fn C.usearch_remove(index voidptr, key u64, err &&char) usize
fn C.usearch_add(index voidptr, key u64, vector voidptr, vector_kind int, err &&char)
fn C.usearch_search(index voidptr, query_vector voidptr, query_kind int, count usize, keys &u64, distances &f32, err &&char) usize
fn C.usearch_size(index voidptr, err &&char) usize
fn C.usearch_save(index voidptr, path &char, err &&char)
fn C.usearch_load(index voidptr, path &char, err &&char)

const usearch_metric_cos_k = 1
const usearch_scalar_f32_k = 1

pub struct USearchVectorBackendConfig {
pub:
	dimensions       int
	capacity         int = 1024
	connectivity     int
	expansion_add    int
	expansion_search int
}

pub struct USearchVectorBackend {
pub:
	config USearchVectorBackendConfig
mut:
	index         voidptr
	branch_by_key map[u64]string
}

pub fn new_usearch_vector_backend(config USearchVectorBackendConfig) !USearchVectorBackend {
	if config.dimensions <= 0 {
		return error('USearch dimensions must be positive')
	}
	mut backend := USearchVectorBackend{
		config:        config
		branch_by_key: map[u64]string{}
	}
	backend.ready()!
	return backend
}

pub fn (backend USearchVectorBackend) kind() string {
	_ = backend
	return 'usearch'
}

pub fn (mut backend USearchVectorBackend) ready() ! {
	if backend.index != unsafe { nil } {
		return
	}
	mut options := C.usearch_init_options_t{
		metric_kind:      usearch_metric_cos_k
		metric:           unsafe { nil }
		quantization:     usearch_scalar_f32_k
		dimensions:       usize(backend.config.dimensions)
		connectivity:     usize(backend.config.connectivity)
		expansion_add:    usize(backend.config.expansion_add)
		expansion_search: usize(backend.config.expansion_search)
		multi:            false
	}
	mut err := &char(unsafe { nil })
	backend.index = C.usearch_init(&options, &err)
	if err != unsafe { nil } {
		return error(usearch_error_message(err))
	}
	if backend.index == unsafe { nil } {
		return error('USearch failed to initialize index')
	}
	if backend.config.capacity > 0 {
		C.usearch_reserve(backend.index, usize(backend.config.capacity), &err)
		if err != unsafe { nil } {
			return error(usearch_error_message(err))
		}
	}
}

pub fn (mut backend USearchVectorBackend) upsert(records []VectorIndexRecord) ! {
	backend.ready()!
	for record in records {
		if record.vector.len != backend.config.dimensions {
			return error('USearch vector dimensions mismatch: expected ${backend.config.dimensions}, got ${record.vector.len}')
		}
		key := usearch_key_from_int_id(record.int_id)!
		mut err := &char(unsafe { nil })
		if C.usearch_contains(backend.index, key, &err) {
			if err != unsafe { nil } {
				return error(usearch_error_message(err))
			}
			_ = C.usearch_remove(backend.index, key, &err)
			if err != unsafe { nil } {
				return error(usearch_error_message(err))
			}
		}
		C.usearch_add(backend.index, key, unsafe { record.vector.data }, usearch_scalar_f32_k,
			&err)
		if err != unsafe { nil } {
			return error(usearch_error_message(err))
		}
		backend.branch_by_key[key] = record.branch_name
	}
}

pub fn (mut backend USearchVectorBackend) query(vector []f32, query VectorIndexQuery) ![]VectorIndexMatch {
	backend.ready()!
	if vector.len != backend.config.dimensions {
		return error('USearch query vector dimensions mismatch: expected ${backend.config.dimensions}, got ${vector.len}')
	}
	limit := if query.limit > 0 { query.limit } else { 10 }
	mut err := &char(unsafe { nil })
	size := C.usearch_size(backend.index, &err)
	if err != unsafe { nil } {
		return error(usearch_error_message(err))
	}
	if size == 0 {
		return []VectorIndexMatch{}
	}
	search_count := usearch_search_count(limit, int(size))
	mut keys := []u64{len: search_count}
	mut distances := []f32{len: search_count}
	found := C.usearch_search(backend.index, unsafe { vector.data }, usearch_scalar_f32_k,
		usize(search_count), unsafe { &keys[0] }, unsafe { &distances[0] }, &err)
	if err != unsafe { nil } {
		return error(usearch_error_message(err))
	}
	mut out := []VectorIndexMatch{cap: limit}
	for idx in 0 .. int(found) {
		key := keys[idx]
		if query.branch_name.len > 0 && backend.branch_by_key.len > 0 {
			branch := backend.branch_by_key[key] or { continue }
			if branch != query.branch_name {
				continue
			}
		}
		out << VectorIndexMatch{
			int_id: i64(key)
			score:  1.0 - f64(distances[idx])
		}
		if out.len >= limit {
			break
		}
	}
	return out
}

pub fn (mut backend USearchVectorBackend) load(path string) ! {
	backend.ready()!
	mut err := &char(unsafe { nil })
	C.usearch_load(backend.index, &char(path.str), &err)
	if err != unsafe { nil } {
		return error(usearch_error_message(err))
	}
}

pub fn (mut backend USearchVectorBackend) save(path string) ! {
	backend.ready()!
	mut err := &char(unsafe { nil })
	C.usearch_save(backend.index, &char(path.str), &err)
	if err != unsafe { nil } {
		return error(usearch_error_message(err))
	}
}

pub fn (mut backend USearchVectorBackend) size() !int {
	backend.ready()!
	mut err := &char(unsafe { nil })
	size := C.usearch_size(backend.index, &err)
	if err != unsafe { nil } {
		return error(usearch_error_message(err))
	}
	return int(size)
}

pub fn (mut backend USearchVectorBackend) close() ! {
	if backend.index == unsafe { nil } {
		return
	}
	mut err := &char(unsafe { nil })
	C.usearch_free(backend.index, &err)
	backend.index = unsafe { nil }
	if err != unsafe { nil } {
		return error(usearch_error_message(err))
	}
}

fn usearch_key_from_int_id(int_id i64) !u64 {
	if int_id < 0 {
		return error('USearch int_id cannot be negative: ${int_id}')
	}
	return u64(int_id)
}

fn usearch_search_count(limit int, size int) int {
	mut count := limit * 4
	if count < limit {
		count = limit
	}
	if count < 16 {
		count = 16
	}
	if count > size {
		count = size
	}
	return count
}

fn usearch_error_message(err &char) string {
	if err == unsafe { nil } {
		return ''
	}
	return unsafe { cstring_to_vstring(err) }
}
