CREATE EXTENSION IF NOT EXISTS clickhouse_fdw;
DROP SERVER IF EXISTS clickhouse_svr CASCADE;
CREATE SERVER clickhouse_svr FOREIGN DATA WRAPPER clickhouse_fdw OPTIONS(dbname 'analytics', driver 'binary', host 'clickhouse-s0-r0');
CREATE USER MAPPING FOR CURRENT_USER SERVER clickhouse_svr OPTIONS (user 'default', password '');
IMPORT FOREIGN SCHEMA "analytics" FROM SERVER clickhouse_svr INTO public;
