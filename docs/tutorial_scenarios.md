# PollyDB Tutorial Scenarios

This companion guide builds on [tutorial.md](/Users/guweigang/Source/pollytree/docs/tutorial.md).
Instead of explaining each command in isolation, it walks through a few realistic scenarios end to end.

## Scenario 1: A Small App Database

This is the simplest useful `pollydb` shape:

- one branch
- one user table
- one secondary index
- simple CRUD

### Initialize

```sh
v run ./cmd/pollydb -- init /tmp/pollydb-app main
cd /tmp/pollydb-app
```

### Register the Table

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-table users id \
  "id:string,name:string,email:string?,active:bool,role:enum(admin|member|guest),created_at:datetime:current_timestamp,updated_at:datetime:current_timestamp:auto_update" \
  "email_idx:email,email_cover:email:covering,role_idx:role"
```

### Insert Rows

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row users u-001 \
  "id=u-001,name=Ada,email=ada@example.com,active=true,role=admin"

v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row users u-002 \
  "id=u-002,name=Grace,email=grace@example.com,active=true,role=member"
```

### Read Back

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- get-row users u-001
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- scan-table users 10
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- lookup-index users email_idx ada@example.com 10
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- prefix-index-projected users email_cover ada "email" 10
```

### Update or Delete

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row users u-002 \
  "id=u-002,name=Grace Hopper,email=grace@example.com,active=true,role=member"

v run /Users/guweigang/Source/pollytree/cmd/pollydb -- delete-row users u-001
```

Because `updated_at` was declared as `datetime:current_timestamp:auto_update`, the second `put-row` refreshes it automatically even though the command does not pass an explicit timestamp.

### Inspect the Database

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- status
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- describe-table users
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- log 10
```

## Scenario 2: Branching Like Git

This is the simplest collaboration story:

- `main` stays stable
- a feature branch diverges
- changes are reviewed via merge preview/report
- the branch is merged back

### Start from Main

```sh
v run ./cmd/pollydb -- init /tmp/pollydb-branches main
cd /tmp/pollydb-branches
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-table users id \
  "id:string,name:string,email:string" \
  "email_idx:email"
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row users 001 \
  "id=001,name=Ada,email=ada@example.com"
```

### Create a Feature Branch

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- create-branch feature
```

### Make Different Changes on Each Branch

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row users 001 \
  "id=001,name=Ada Lovelace,email=ada@example.com"

v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row feature users 002 \
  "id=002,name=Grace,email=grace@example.com"
```

### Review Before Merge

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-base main feature
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-preview main feature
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-report main feature 10
```

### Merge

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- merge-branch main feature
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- scan-table users 10
```

If there are conflicts, `merge-report` gives the best current explanation surface because it includes:

- changed tables
- changed keys
- conflict keys
- decoded `base / ours / theirs` row previews when available

## Scenario 3: JSON Documents with Indexed Paths

This scenario is useful for event payloads, flexible metadata, and AI notebook data.

### Register a Table with JSON and JSON-Path Indexes

```sh
v run ./cmd/pollydb -- init /tmp/pollydb-json main
cd /tmp/pollydb-json

v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-table items id \
  "id:string,status:enum(active|draft),meta:json,enabled:bool" \
  "status_idx:status,kind_idx:meta.kind:string,kind_cover:meta.kind:string:covering,code_idx:meta.kind.code:string,enabled_idx:meta.enabled:bool:covering"
```

### Insert JSON Rows

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row items 001 \
  "id=001,status=active,enabled=true,meta={\"kind\":{\"code\":\"alpha\",\"label\":\"A\"},\"enabled\":true}"

v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row items 002 \
  "id=002,status=draft,enabled=false,meta={\"kind\":{\"code\":\"beta\",\"label\":\"B\"},\"enabled\":false}"
```

### Query by JSON Path

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- lookup-index items code_idx alpha 10
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- prefix-index items kind_cover a 10
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- prefix-index-projected items kind_cover a "meta" 10
```

### Update Nested JSON Paths

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- set-json-path items 001 meta kind.code string gamma
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- null-json-path items 001 meta enabled
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- delete-json-path items 001 meta kind.label
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- patch-json-paths items 002 meta \
  "kind.code=string:delta,enabled=bool:true,obsolete=delete"
```

These operations keep JSON-path indexes up to date automatically.

## Scenario 4: Built-In Aggregates for Fast Counts and Sums

Use declared aggregate columns when you want fast table-level or range-level aggregate reads.

### Register a Table with a Declared Sum Column

```sh
v run ./cmd/pollydb -- init /tmp/pollydb-metrics main
cd /tmp/pollydb-metrics

v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-table metrics id \
  "id:i64:sum,name:string" \
  "-"
```

### Insert Data

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row metrics 1 "id=1,name=one"
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row metrics 2 "id=2,name=two"
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row metrics 3 "id=3,name=three"
```

### Query Fast Aggregates

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- count-rows metrics
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- count-rows-range metrics 1 3
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- sum-column metrics id
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- sum-column-range metrics id 1 3
```

Use this when:

- the aggregate is core to the table
- it is known up front
- you want fast built-in reads without an extra projector lifecycle

## Scenario 5: Aggregate Projectors for Optional or Late-Bound Aggregates

Use an aggregate projector when:

- you do not want to keep growing the main tree metadata
- the aggregate is optional or experimental
- you want to add it later
- you want asynchronous catch-up

### Register a Table

```sh
v run ./cmd/pollydb -- init /tmp/pollydb-projectors main
cd /tmp/pollydb-projectors

v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-table items id \
  "id:string,payload:json" \
  "amount_idx:payload.amount.total:i64"
```

### Register Aggregate Projectors

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-aggregate-projection sum_payload_total items payload amount.total 500 low
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- register-aggregate-projection sum_payload_total_backup items payload amount.total 100 high
```

### Write Data First

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row items 001 \
  "id=001,payload={\"amount\":{\"total\":10}}"

v run /Users/guweigang/Source/pollytree/cmd/pollydb -- put-row items 002 \
  "id=002,payload={\"amount\":{\"total\":15}}"
```

At this point projector state may be stale:

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- projectors
```

### Refresh with Different Policies

```sh
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- refresh-aggregate-projections stale_one
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- refresh-aggregate-projections stale_up_to 2
v run /Users/guweigang/Source/pollytree/cmd/pollydb -- refresh-aggregate-projections stale_all
```

The current selection rule for limited budgets is:

1. higher `priority`
2. lower `cost_hint`
3. name order

This gives you a practical way to say:

- refresh important cheap projectors first
- let expensive or low-priority projectors lag behind

## Scenario 6: When to Use Which Aggregate Path

### Use Declared `:sum`

Use declared `:sum` when:

- the aggregate is part of the table design
- it is simple and stable
- you want fast built-in table/range `SUM`

### Use an Aggregate Projector

Use a projector when:

- you want an aggregate after the table already exists
- you want async catch-up
- you want different refresh policies
- you do not want to keep growing the main tree contract

### Use a Plain Scan

Use a plain scan when:

- the aggregate is ad hoc
- the query is rare
- you do not want to maintain extra metadata

## Scenario 7: Recommended First Workflow

If you are just getting started, this is the best current progression:

1. Start with `init`
2. Register one typed table
3. Add one normal index and one covering index
4. Insert and query a few rows
5. Create a branch and test merge preview/report
6. Add one JSON column and one JSON-path index
7. Add declared `:sum` only where it is clearly worth it
8. Add aggregate projectors for everything optional, delayed, or expensive

That path lines up best with the current strengths of `pollydb`.
