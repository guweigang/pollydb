# `vsql` Query Mapping Note

This note describes how a future `vsql` query layer should map simple SQL
filters onto the query/planner surface that PollyDB already exposes today.

It is intentionally focused on single-table filtering.
It does not define SQL grammar.

## Purpose

The goal is to keep `vsql` thin where possible:

- parse SQL into an internal expression tree
- normalize a small subset of predicates
- validate them against `TableQuerySchema`
- lower them into `QueryRequest`
- optionally call `preview_query_plan_details(...)` for diagnostics
- execute through `query_page(...)`

The preferred lowering path is now:

1. SQL AST
2. `SqlFilterFragment`
3. `NormalizedQueryPredicate`
4. `QueryPredicateSpec`
5. `QueryRequest`

That means `vsql` should reuse PollyDB for:

- filter legality
- selector/index capability lookup
- continuation/page semantics
- request-time planner preview

## Main Mapping

For the currently supported lightweight query layer, `vsql` should map:

- `SELECT ... FROM t WHERE col = ?`
  - to `QueryFilter.eq(...)`
- `SELECT ... FROM t WHERE col LIKE 'prefix%'`
  - to `QueryFilter.prefix(...)`
- `SELECT ... FROM t WHERE col > ?`
  - to `QueryFilter.after(...)`
- `SELECT ... FROM t WHERE col < ?`
  - to `QueryFilter.before(...)`
- `SELECT ... FROM t WHERE col BETWEEN ? AND ?`
  - to `QueryFilter.between(...)`

For field-selector-backed predicates, `vsql` should map:

- `markdown_selector(body, 'heading_text:2') LIKE 'Road%'`
  - to `QueryFilter.field_prefix('body', 'markdown', 'heading_text:2', 'Road')`
- `markdown_selector(body, 'link_host') = 'docs.example.com'`
  - to `QueryFilter.field_eq('body', 'markdown', 'link_host', 'docs.example.com')`
- `markdown_metric(body, 'links') > 1`
  - to `QueryFilter.field_after('body', 'markdown', 'links', i64(1))`

The exact SQL function names are still a `vsql` decision.
What matters here is the lowering target:

- base column predicates become ordinary `QueryFilter`
- capability-backed predicates become field-selector `QueryFilter`

In implementation terms, `vsql` should preferably:

- lower SQL syntax into `SqlPredicateAdapterInput`
- adapt that into `SqlFilterFragment`
- convert that into `NormalizedQueryPredicate`
- convert that into `QueryPredicateSpec`
- let PollyDB validate and lower the result into `QueryRequest`

## Validation Flow

For each lowered predicate, `vsql` should:

1. resolve the target table
2. load `TableQuerySchema`
3. find the target column or field selector capability
4. confirm the requested operator is present in `filter_shapes`
5. confirm the value type matches `value_type`

Recommended rule:

- if a predicate cannot be represented as a current `QueryFilter`, reject it at
  the `vsql` layer rather than silently degrading into a different meaning

## Planner-Relevant Metadata

`vsql` should treat these `TableQuerySchema` fields as authoritative:

- `columns[*].filter_shapes`
- `field_selectors[*].filter_shapes`
- `indexes[*]`
- `projection_metrics[*]`

Most important fields inside each `filter_shape` are:

- `indexed`
- `index_name`
- `planner_strategy`
- `projection_only`
- `continuation_anchor`
- `sample_explain`

Recommended interpretation:

- `indexed=true`
  - planner can expect a direct index-backed strategy
- `projection_only=true`
  - shape is legal but currently not index-backed
- `continuation_anchor=true`
  - index-shaped paging should be stable for that filter shape

## Combining Multiple Predicates

The current query core chooses one best filter as the primary planner filter and
applies the rest as post-filters.

So for a query like:

```sql
SELECT title
FROM notes
WHERE markdown_selector(body, 'heading_text:2') LIKE 'Road%'
  AND title = 'Doc'
```

`vsql` should lower to:

```text
QueryRequest{
  table_name: 'notes'
  filters: [
    QueryFilter.field_prefix('body', 'markdown', 'heading_text:2', 'Road')
    QueryFilter.eq('title', 'Doc')
  ]
  select_columns: ['title']
}
```

Then PollyDB's planner is expected to choose:

- primary filter: `body / markdown / heading_text:2 / prefix`
- planner strategy: `index_prefix`
- remaining filter: `title = 'Doc'` as post-filter

This is exactly the kind of decision `preview_query_plan_details(...)` should
surface back to `vsql`.

## Explain Integration

There are two good integration points for `vsql` diagnostics.

### Static Diagnostics

When validating a query shape before execution, `vsql` can use:

- `filter_shapes[*].sample_explain`

This is useful for:

- editor hints
- linting
- basic "this query will scan" warnings

### Request Diagnostics

When planning an actual query request, `vsql` can use:

- `preview_query_plan_details(...)`
- or Sidecar `POST /v1/query-plan-preview`

Recommended usage:

- show `preview.sample_explain()` as the canonical planner summary
- treat top-level preview `warnings` and `notes` as compatibility fields only

## Current Lowering Limits

Today `vsql` should only lower predicates that fit this model cleanly:

- single-table predicates
- conjunctions (`AND`)
- direct scalar comparisons
- prefix-like string comparisons
- field-selector predicates already represented in `TableQuerySchema`

It should not yet try to lower:

- `OR`
- arbitrary nested boolean logic
- join predicates
- subqueries
- aggregate `HAVING`
- arbitrary function expressions that PollyDB cannot map to a field selector

## Suggested Implementation Order

When `vsql` starts consuming this layer, a low-risk order is:

1. plain column `eq`
2. plain column `prefix`
3. plain range filters
4. field-selector exact/prefix filters
5. field-selector numeric range filters
6. request-time planner preview integration

## Relationship to Other Docs

Use this document together with:

- [Query Planner Introspection](/Users/guweigang/Source/pollytree/docs/query_planner_introspection.md)
- [Storage API](/Users/guweigang/Source/pollytree/docs/storage_api.md)

This note is the translation layer.
The introspection doc defines the metadata contract.
The storage API doc defines the concrete callable API surface.
