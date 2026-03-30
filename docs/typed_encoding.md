# Typed Encoding And Index Contract

This document defines how typed rows and secondary-index keys are encoded in `pollydb`.

## Design Rules

- Encoding must be deterministic.
- Equal logical values must produce bit-for-bit identical bytes.
- Indexed values must preserve logical sort order in byte order.
- `NULL` handling must be explicit.
- Secondary index entries must remain stable under structural sharing.

## Column Types

Current typed storage supports:

- `bool_`
- `i64_`
- `string_`
- `bytes_`

`NULL` is represented explicitly through `NullValue` and column nullability.

## Row Encoding

Typed rows are encoded by `TypedRowCodec`.

The row layout is:

```text
[column_count:u32]
repeat for each declared column, in schema order:
  [present:u8]
  [payload_len:u32]
  [payload bytes]
```

Rules:

- Columns are encoded in `TableDef.columns` order.
- Missing non-nullable columns are rejected.
- `present = 0` means `NULL` and `payload_len = 0`.
- `present = 1` means a typed payload follows.
- Row encoding is schema-driven, not map-iteration-driven.

This makes row payloads deterministic across processes and versions, as long as the table schema is unchanged.

## Value Encoding

### `bool_`

Payload encoding:

```text
false -> [0x00]
true  -> [0x01]
```

Index ordering:

```text
false < true
```

### `i64_`

Row payload encoding:

- 8-byte little-endian signed integer payload

Index encoding:

- Apply sign-bit transform: `u64(value) ^ 0x8000_0000_0000_0000`
- Encode transformed value as 8-byte big-endian

This gives bytewise order equal to logical integer order:

```text
-10 < 0 < 10
```

### `string_`

Payload encoding:

- Raw UTF-8 bytes

Index ordering:

- Binary byte-order comparison over UTF-8 bytes

This is intentionally a binary collation contract for now. Locale-aware collation should be treated as a future layer above storage.

### `bytes_`

Payload encoding:

- Raw bytes

Index ordering:

- Binary byte-order comparison

## `NULL` Ordering

Nullable indexed columns are encoded with a leading tag:

```text
NULL     -> [0x00]
non-NULL -> [0x01] + encoded typed payload
```

This gives the storage-level ordering rule:

```text
NULL < any non-NULL value
```

That rule should remain stable unless we intentionally version the storage contract.

## Primary Key And Row Keys

Table rows are stored under:

```text
"t|" + table_name + "|" + primary_key_bytes
```

The `primary_key_bytes` portion is provided by the caller. For `vsql`, this should eventually be generated from typed primary-key columns using a deterministic primary-key codec.

## Secondary Index Keys

Secondary index entries are stored under:

```text
"i|" + table_name + "|" + index_name + "|" + encoded_index_value + "|" + primary_key_bytes
```

Properties:

- The suffix `primary_key_bytes` makes duplicate index values unique.
- Range and prefix scans work naturally over the encoded index value.
- Index entries can be rebuilt from table rows deterministically.

## Why Primary Key Is Suffixed To Secondary Index Entries

This is required for three reasons:

1. Multiple rows may share the same indexed value.
2. A unique tree key is required for deterministic storage.
3. The primary key suffix makes index lookup return the exact row identity without an extra uniqueness layer.

## Merge And Index Rebuild Rule

Three-way merge currently operates on raw tree items. For typed tables, this means merge conflict resolution may directly rewrite row payloads.

After typed merge resolution, `pollydb` must rebuild typed secondary-index entries from the merged row set. This is now part of the typed merge workflow and should be considered part of the storage contract.

## Invariants To Preserve

Any future change to typed encoding should preserve these invariants unless we explicitly version the format:

- Same typed row input -> same row bytes
- Same indexed value -> same index bytes
- Bytewise comparison of index keys matches logical comparison
- Merge + rebuild produces the same secondary-index state as fresh insert/update
- Schema order, not map order, determines row layout

## Performance Checklist For The Next Phase

Before calling this storage engine production-ready for `vsql`, benchmark at least:

- 1M row bulk insert
- 1M row point lookup set
- range scan over sorted `i64_` primary keys
- secondary-index lookup on `string_`
- update workload with index maintenance
- merge workload with typed index rebuild
- chunk reuse ratio after small edits
