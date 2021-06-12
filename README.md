# Distributed clickhouse

Sets up standalone zookeeper to coordinate a clickhouse cluster consisting of
  	- two shards
	- two replicas per shard
	- postgres with [clickhouse foreign data wrapper](https://github.com/adjust/clickhouse_fdw) to access clickhouse

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
$ bash script/connect {servername} [option]
```

where servername is any of the `clickhouse-s{\d}-r{\d}` listed above.

## License

WTFPL

