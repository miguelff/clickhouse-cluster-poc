create database if not exists analytics on cluster 'cluster_01';

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
--      * parameterized_query_hash -> query_hash, changed from string to fixed string of 40 bytes, as it's a sha1
--      * user_vars -> session_vars
--      * execution_time -> latency
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
CREATE TABLE IF NOT EXISTS analytics.operation_logs_local ON CLUSTER 'cluster_01' (
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
    query_hash FixedString(40), -- LOGICAL: formerly parameterized_query_hash Nullable(String), it's sha1 so 40 bytes.
    session_vars String DEFAULT '{}', --LOGICAL: formerly user_vars, it's json.
    request_size Nullable(Int32), -- LOGICAL
    response_size Nullable(Int32), -- LOGICAL
    latency Decimal64(12) DEFAULT 0, -- LOGICAL: formerly execution_time
    request_read_time Decimal64(12) DEFAULT 0, -- LEGACY
    error Nullable(String), -- LOGICAL: is_error was removed as (is_error equals to (error != NULL))
    error_code Nullable(String), -- LEGACY
    http_info Nullable(String), -- LEGACY
    websocket_id Nullable(UUID), -- LEGACY
    ws_operation_id Nullable(String), -- LEGACY
    kind Nullable(String), -- LEGACY
    generated_sql Nullable(String) -- LEGACY
) ENGINE = ReplicatedMergeTree('/clickhouse/cluster_01/tables/analytics/operation_logs/{shard}', '{replica}')
  ORDER BY (project_id, timestamp)
  PARTITION BY toStartOfTenMinutes(timestamp)
  TTL timestamp + INTERVAL 1 MONTH DELETE;

CREATE TABLE IF NOT EXISTS analytics.operation_logs ON CLUSTER 'cluster_01'
    AS analytics.operation_logs_local
ENGINE = Distributed('cluster_01', 'analytics', 'operation_logs_local', rand());
