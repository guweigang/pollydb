# Query Planner Introspection

This document defines the current planner-facing metadata surface that sits
between PollyDB storage/query internals and the future `vsql` layer.

It is intentionally not a second query language.
Its job is to answer:

- what a table can be queried by
- which filter shapes are legal
- which indexes or projections back those shapes
- what the planner is likely to do for a representative filter

## Scope

This layer is for:

- storage-facing SDKs
- Sidecar clients
- future `vsql` validation and planning
- query UIs and debugging tools

This layer is not for:

- SQL parsing
- SQL syntax trees
- join planning
- a user-authored DSL

## Core Objects

The current storage-facing objects are:

- `TableQuerySchema`
- `QueryColumnCapability`
- `QueryIndexCapability`
- `QueryFieldSelectorCapability`
- `QueryProjectionCapability`
- `QueryFilterShapeCapability`
- `QuerySamplePlanExplain`
- `QueryPlanPreview`

Together they describe:

- legal filter operators per column or selector
- index-backed vs projection-only shapes
- continuation compatibility
- a sample planner explanation for each filter shape

## Two Explain Surfaces

PollyDB now exposes two related explain surfaces.

### 1. Schema-Time Explain

`table_query_schema(...)` returns a stable capability view.

For each `filter_shape`, it includes:

- `op`
- `value_type`
- `indexed`
- `index_name`
- `planner_strategy`
- `planner_score`
- `projection_only`
- `continuation_anchor`
- `sample_explain`

`sample_explain` is the smallest reusable planner summary for that shape.

It includes:

- `strategy`
- `index_name`
- `warnings`
- `notes`
- `default_result_shape`
- `supports_continuation_token`

This is the preferred metadata surface for future `vsql` capability checks.

### 2. Request-Time Explain

`preview_query_plan_details(...)` and `POST /v1/query-plan-preview` return a
request-specific `QueryPlanPreview`.

That object contains:

- the concrete `plan`
- compatibility fields:
  - `warnings`
  - `notes`
  - `default_result_shape`
  - `supports_continuation_token`

It also exposes:

- `sample_explain()`

`sample_explain()` intentionally matches the same shape used by
`QueryFilterShapeCapability.sample_explain`.

This means:

- schema-time introspection and request-time preview now share one explain model
- future `vsql` can consume one explain shape from both paths

## Why This Does Not Duplicate `vsql`

`vsql` should own:

- SQL syntax
- parsing
- semantic analysis
- rewrite/planning decisions at the SQL layer

This introspection layer owns:

- capability metadata
- planner hints
- selector availability
- explain payload shape

In other words:

- `vsql` decides how a user query is expressed
- PollyDB introspection decides what the storage/query engine can do

## Current Sidecar Endpoints

The current planner-facing Sidecar endpoints are:

- `GET /v1/query-schema`
- `POST /v1/query-plan-preview`

Recommended usage:

1. call `query-schema` to learn legal filter shapes
2. map a user request into `QueryRequest`-like filters
3. call `query-plan-preview` when a request-specific explanation is needed

For a more concrete SQL-to-storage lowering guide, see [vsql_query_mapping.md](/Users/guweigang/Source/pollytree/docs/vsql_query_mapping.md).

## Recommended Consumer Rules

For new integrations:

- prefer `query_page(...)` over `query_rows(...)`
- prefer `QueryPlanPreview.sample_explain()` over duplicated top-level preview fields
- prefer `filter_shapes[*].sample_explain` for static capability UIs
- treat top-level `warnings` and `notes` on preview results as compatibility fields

For future `vsql`:

- use `TableQuerySchema` for validation
- use `filter_shapes` for legal-op checks
- use `sample_explain` for planner-facing hints in diagnostics
- use `preview_query_plan_details(...)` only when planning a concrete request

## Current Limits

This layer is intentionally small.

It does not yet model:

- joins
- multi-index combination planning
- cost-based cardinality estimates
- full predicate normalization
- planner memo structures

That is expected.
The goal is to provide a stable single-table capability and explain contract
that `vsql` can build on, not to pre-build an entire SQL optimizer.
