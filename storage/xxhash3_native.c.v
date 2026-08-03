module storage

$if windows {
	#flag windows -I @VMODROOT/thirdparty/native/include
	#flag windows @VMODROOT/thirdparty/native/lib/xxhash.lib
} $else $if $pkgconfig('libxxhash') {
	#pkgconfig --cflags --libs libxxhash
} $else {
	#flag darwin -I/opt/homebrew/include
	#flag darwin -L/opt/homebrew/lib -lxxhash
	#flag linux -lxxhash
}

#include <xxhash.h>

fn C.XXH3_64bits(data voidptr, len usize) u64
fn C.XXH3_64bits_withSeed(data voidptr, len usize, seed u64) u64

const xxh3_secondary_seed = u64(0x9e3779b97f4a7c15)

fn xxh3_sum128_ptr(data &u8, len int) []u8 {
	mut data_ptr := voidptr(0)
	if len > 0 {
		data_ptr = data
	}
	high := C.XXH3_64bits(data_ptr, usize(len))
	low := C.XXH3_64bits_withSeed(data_ptr, usize(len), xxh3_secondary_seed)
	mut out := []u8{len: 16}
	xxh3_write_u64_be(mut out, 0, high)
	xxh3_write_u64_be(mut out, 8, low)
	return out
}

fn xxh3_write_u64_be(mut out []u8, offset int, value u64) {
	out[offset + 0] = u8((value >> 56) & 0xff)
	out[offset + 1] = u8((value >> 48) & 0xff)
	out[offset + 2] = u8((value >> 40) & 0xff)
	out[offset + 3] = u8((value >> 32) & 0xff)
	out[offset + 4] = u8((value >> 24) & 0xff)
	out[offset + 5] = u8((value >> 16) & 0xff)
	out[offset + 6] = u8((value >> 8) & 0xff)
	out[offset + 7] = u8(value & 0xff)
}
