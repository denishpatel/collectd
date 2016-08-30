create role collectd login encrypted password 'XXXX';
create schema collectd;
set search_path = collectd,pg_catalog;
ALTER ROLE collectd SET statement_timeout=60000;
grant usage on schema collectd to collectd;
alter role collectd set search_path = collectd,pg_catalog;

-- pg_stat_activity

create or replace function pg_stat_activity() returns setof pg_catalog.pg_stat_activity as $$begin return query(select * from pg_catalog.pg_stat_activity); end$$ language plpgsql security definer;
revoke all on function pg_stat_activity() from public;
grant execute on function pg_stat_activity() to collectd;

create or replace view pg_stat_activity as select * from pg_stat_activity();
revoke all on collectd.pg_stat_activity from public;
grant select on pg_stat_activity to collectd;

-- install pg_stat_statements

create extension IF NOT EXISTS pg_stat_statements WITH SCHEMA collectd;
alter schema collectd owner to collectd;

CREATE OR REPLACE FUNCTION collectd.get_stat_statements() RETURNS SETOF pg_stat_statements AS
$$
  SELECT * FROM pg_stat_statements
  WHERE dbid IN (SELECT oid FROM pg_database WHERE datname = current_database());
$$ LANGUAGE sql VOLATILE SECURITY DEFINER;

-- Find Seq scan on large tables
DROP MATERIALIZED VIEW IF EXISTS collectd.seq_scan_on_large_tables;

CREATE MATERIALIZED VIEW collectd.seq_scan_on_large_tables AS
  SELECT relid, schemaname, relname, seq_scan, seq_tup_read , pg_relation_size(relid) as relsize, now() as refreshed_at
     FROM pg_stat_all_tables
        WHERE pg_relation_size(relid) > 1073741824
           AND schemaname not in ('pg_catalog', 'information_schema')
  UNION ALL SELECT 0,'0','0','0',0,0,now();

ALTER materialized VIEW collectd.seq_scan_on_large_tables OWNER TO collectd;

CREATE OR REPLACE FUNCTION collectd.get_seq_scan_on_large_tables()
RETURNS text AS
$$

DECLARE
  v_matview text;
  v_refreshed_at timestamptz;
  v_tables_with_seq_scan text[];
BEGIN
 SELECT refreshed_at INTO v_refreshed_at
        FROM  collectd.seq_scan_on_large_tables WHERE relid=0;
  -- refresh MV every 4 hours
  IF v_refreshed_at < now() - interval '4 hours' and pg_is_in_recovery() is false THEN
     REFRESH  MATERIALIZED VIEW collectd.seq_scan_on_large_tables;
  END IF;

 SELECT ARRAY (SELECT base.relname ||':'||  (current.seq_scan-base.seq_scan) INTO v_tables_with_seq_scan
        FROM collectd.seq_scan_on_large_tables AS base
          LEFT JOIN pg_stat_all_tables AS current ON (base.schemaname=base.schemaname AND base.relname=current.relname)
            WHERE (current.seq_scan-base.seq_scan) > 0 AND ((current.seq_tup_read-base.seq_tup_read)/(current.seq_scan-base.seq_scan)) > 50000  ) AS tables_with_seq_scan;

   IF v_tables_with_seq_scan = '{}' THEN
     RETURN 'OK';
  ELSE
     RETURN  'PROBLEM: Seq scan on table: '|| array_to_string(v_tables_with_seq_scan,'&');
   END If;
END;
$$
LANGUAGE 'plpgsql' SECURITY DEFINER;
alter function collectd.get_seq_scan_on_large_tables() owner to collectd;
revoke all on function get_seq_scan_on_large_tables() from public;
grant execute on function get_seq_scan_on_large_tables() to collectd;

drop view IF EXISTS get_seq_scan_on_large_tables;
create view get_seq_scan_on_large_tables as select * from get_seq_scan_on_large_tables();
revoke all on collectd.get_seq_scan_on_large_tables from public;
grant select on get_seq_scan_on_large_tables to collectd;
