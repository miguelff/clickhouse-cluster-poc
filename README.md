# Distributed clickhouse

Sets up standalone zookeeper to coordinate a clickhouse cluster consisting of
  - two shards
  - two replicas per shard
  - postgres with [clickhouse foreign data wrapper](https://github.com/adjust/clickhouse_fdw)

## How To Use

`script/setup` will:

- Use docker compose to setup the cluster
- Load the schema as per `sql/create.sql`
- Load the data as per `sql/insert.sql`

The container names (and main listening ports) for the cluster nodes are:

- clickhouse-s0-r0 (9000)
- clickhouse-s1-r0 (9001)
- clickhouse-s0-r1 (9002)
- clickhouse-s1-r1 (9003)
- zookeeper (2181)

To connect to clickhouse, you can execute the following command:

```bash
$ bash script/ch-connect {servername} [option]
```

where servername is any of the `clickhouse-s{\d}-r{\d}` listed above.

To fill clickhouse with data run:

`script/generate-data`

```
Options:
	--table: table to populatem defaults to `operation_logs`
	--rows: number of rows to fill in, defaults to 200000
	--projects: number of different projects filling data, defaults to 10
	--queries: number of different queries issued, defaults to 100
	--rps: number of requests with the same timestamp, defaults to 1000
```

By default, 20,000 rows will be inserted by 10 different projects, using a random sample of 100 queries, spanning 20 seconds.

## PoC schema

![Diagram](poc.png)

This is subject to vary, but in essence, postgres serves as a front-end for a clickhouse cluster of 2 shards, two replicas each
in which there are two schemas `analytics`, and `analytics_internal`. `analytics` contains tables and views accessed directly by
the clients connected through the postgres front-end, and `analytics_internal` definitions of materialized views with intermediate
representations of the data.

## Container bootstrap process

1. Start zookeeper
1. Start all clickhouse nodes except clickhouse-s0-r0
1. Start clickhouse-s0-r0 (9000) and load [db-init-scripts/clickhouse/init-db.sql](db-init-scripts/clickhouse/init-db.sql) to create distributed tables and data
1. Start postgres and load [db-init-scripts/postgres/init-db.sql](db-init-scripts/postgres/init-db.sql) to enable the FDW and import the remote schema

## License

WTFPL

