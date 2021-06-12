create database if not exists analytics on cluster 'cluster_01';

CREATE TABLE IF NOT EXISTS analytics.events_local ON CLUSTER 'cluster_01' (
  EventDate DateTime,
  CounterID UInt32,
  UserID UInt32
) ENGINE = ReplicatedMergeTree('/clickhouse/cluster_01/tables/analytics/events_local/{shard}', '{replica}')
ORDER BY (CounterID, EventDate, intHash32(UserID))
PARTITION BY toYYYYMM(EventDate);

CREATE TABLE IF NOT EXISTS analytics.events ON CLUSTER 'cluster_01'
AS analytics.events_local
ENGINE = Distributed('cluster_01', 'analytics', 'events_local', rand());
