-- analytics contains table and view definitions that can be imported by postgres FDW and are accessed by the clients
CREATE DATABASE analytics on cluster 'cluster_01';
-- analytics_internal contains table and view definitions that are not accessed by clients or cannot be imported in postgres
-- through the FDW, an example is operation_logs_minutely_agg that has incompatible data types
-- like AggregateFunction(quantiles(0.5, 0.9, 0.95, 0.99), UInt64),
CREATE DATABASE analytics_internal on cluster 'cluster_01';

-- New required logical layout: https://docs.google.com/document/d/1Bey4IluXJKCuq5zl70tVgpSnbuRsV44LuYPxGODGtTA/edit#
--
-- Existing Timescale physical layout:
--                               Table "public.operation_logs"
--           Column          |           Type           | Collation | Nullable |  Default
-- --------------------------+--------------------------+-----------+----------+------------
--  time                     | timestamp with time zone |           | not null |
--  project_id               | uuid                     |           | not null |
--  server_client_id         | text                     |           |          |
--  db_uid                   | text                     |           |          |
--  instance_uid             | text                     |           | not null |
--  level                    | text                     |           | not null |
--  request_id               | text                     |           | not null |
--  user_role                | text                     |           | not null |
--  user_vars                | json                     |           | not null | '{}'::json
--  client_name              | text                     |           |          |
--  operation_id             | text                     |           |          |
--  request_read_time        | numeric                  |           | not null | 0
--  is_error                 | boolean                  |           | not null | false
--  error                    | json                     |           |          |
--  error_code               | text                     |           |          |
--  query                    | json                     |           |          |
--  transport                | text                     |           | not null |
--  generated_sql            | json                     |           |          |
--  request_size             | integer                  |           |          |
--  response_size            | integer                  |           |          |
--  http_info                | json                     |           |          |
--  url                      | text                     |           |          |
--  websocket_id             | uuid                     |           |          |
--  ws_operation_id          | text                     |           |          |
--  kind                     | text                     |           |          |
--  parameterized_query_hash | text                     |           |          |
-- Indexes:
--     "operation_logs_operation_index" btree (project_id, operation_name, operation_id, "time" DESC)
--     "operation_logs_request_id_index" btree (project_id, request_id)
--     "operation_logs_time_idx" btree ("time" DESC)
--     "operation_logs_ws_operation_index" btree (project_id, websocket_id, ws_operation_id) WHERE transport = 'ws'::text
-- Triggers:
--     ts_cagg_invalidation_trigger AFTER INSERT OR DELETE OR UPDATE ON operation_logs FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.continuous_agg_invalidation_trigger('27')
--     ts_insert_blocker BEFORE INSERT ON operation_logs FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker()
--
--  Changes:
--  * Fields renamed:
--      * time -> timestamp
--      * user_role -> role
--      * parameterized_query_hash: changed from string to fixed string of 40 bytes, as it's a sha1
--      * user_vars -> session_vars
--      * execution_time -> latency: also changed type be an Int32 (number of milli or microseconds and not a decimal)
--      * request_read_time: changed to be an Int32 (number of milli or microseconds and not a decimal)
-- * Fields removed:
--      * db_uid (deprecated)
--      * is_error (derived from error != NULL)
--      * level (always info)
--      * url (always v1/graphql)
--
-- Tags in the column mean:
--     * LOGICAL: It is required by the new model spec, which is a logical view, regardless of whether it was already
--    present in the existing physical model or not.
--     * LEGACY: It is present in the existing physical model, although not required by the new model spec, it's there
--    for backwards compatibility.
CREATE TABLE analytics_internal.operation_logs_local ON CLUSTER 'cluster_01' (
    project_id UUID, -- LOGICAL
    timestamp DateTime, -- LOGICAL: formerly time
    request_id String, -- LOGICAL
    server_client_id Nullable(String), -- LEGACY
    instance_uid UUID, -- LEGACY
    client_name Nullable(String), -- LEGACY
    operation_type Nullable(String), -- LOGICAL
    operation_name Nullable(String), -- LOGICAL
    operation_id Nullable(String), -- LEGACY
    transport String, -- LEGACY (it might be replaced with materialized column, based on: websocket_id != NULL THEN ws ELSE http)
    role String, -- LOGICAL: formerly user_role
    query Nullable(String), -- LOGICAL
    parameterized_query_hash FixedString(40), -- LEGACY
    session_vars String DEFAULT '{}', --LOGICAL: formerly user_vars, it's json.
    request_size Nullable(UInt32), -- LOGICAL
    response_size Nullable(UInt32), -- LOGICAL
    latency UInt32 DEFAULT 0, -- LOGICAL: formerly execution_time
    request_read_time UInt32 DEFAULT 0, -- LEGACY
    error Nullable(String), -- LOGICAL: is_error was removed as (is_error equals to (error != NULL))
    error_code Nullable(String), -- LEGACY
    http_info Nullable(String), -- LEGACY
    websocket_id Nullable(UUID), -- LEGACY
    ws_operation_id Nullable(String), -- LEGACY
    kind Nullable(String), -- LEGACY
    generated_sql Nullable(String) -- LEGACY
) ENGINE = ReplicatedMergeTree('/clickhouse/cluster_01/tables/analytics_internal/operation_logs_local/{shard}', '{replica}')
  ORDER BY (project_id, timestamp)
  PARTITION BY toStartOfTenMinutes(timestamp)
  TTL timestamp + INTERVAL 1 MONTH DELETE;

CREATE TABLE analytics.operation_logs ON CLUSTER 'cluster_01'
    AS analytics_internal.operation_logs_local
ENGINE = Distributed('cluster_01', 'analytics_internal', 'operation_logs_local', rand());

-- This table will provide the storage for the minutely aggregations materialized view.
-- We will have a non-materialized view on top of this to ease queries.
CREATE TABLE analytics_internal.operation_logs_minutely_agg ON CLUSTER 'cluster_01' (
   project_id UUID,
   time_bucket DateTime,
   role String,
   operation_type Nullable(String), -- this cannot be null here and the materialized view triggers need to take into account that
   operation_name Nullable(String), -- this cannot be null here and the materialized view triggers need to take into account that
   parameterized_query_hash FixedString(40),
   request_size_avg AggregateFunction(avg, Nullable(UInt32)),
   response_size_avg AggregateFunction(avg, Nullable(UInt32)),
   response_size_max AggregateFunction(max, Nullable(UInt32)),
   response_size_quantiles AggregateFunction(quantiles(0.5, 0.9, 0.95, 0.99), UInt32),
   latency_avg AggregateFunction(avg, UInt32),
   latency_max AggregateFunction(max, UInt32),
   latency_quantiles AggregateFunction(quantilesTiming(0.5, 0.9, 0.95, 0.99), UInt32),
   err_count UInt32,
   count UInt32,
   INDEX operation_type_idx operation_type TYPE bloom_filter() GRANULARITY  1
) ENGINE = ReplicatedAggregatingMergeTree('/clickhouse/cluster_01/tables/analytics_internal/operation_logs_minutely_agg_local/{shard}', '{replica}')
PARTITION BY tuple() -- TODO: not partitioned and not distributed yet. Sizes must be low.
ORDER BY (project_id, time_bucket, parameterized_query_hash)
SETTINGS allow_nullable_key = 1;

CREATE MATERIALIZED VIEW analytics_internal.operations_longs_minutely_mv ON CLUSTER 'cluster_01'
TO analytics_internal.operation_logs_minutely_agg
AS SELECT
    project_id,
    toStartOfMinute(timestamp) as time_bucket,
    role,
    parameterized_query_hash,
    operation_type,
    operation_name,
    avgState(request_size) as request_size_avg,
    avgState(response_size) as response_size_avg,
    maxState(response_size) as response_size_max,
    avgState(latency) as latency_avg,
    maxState(latency) as latency_max,
    quantilesTimingState(0.5, 0.9, 0.95, 0.99)(latency) as latency_quantiles,
    countIf(isNotNull(error)) as err_count,
    count(*) as count
FROM analytics.operation_logs
GROUP BY (project_id, time_bucket, role, parameterized_query_hash, operation_type, operation_name);


