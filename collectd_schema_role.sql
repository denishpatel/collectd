create role collectd login encrypted password 'testing';
create schema collectd;
set search_path = collectd,pg_catalog;
grant usage on schema collectd to collectd;
alter role collectd set search_path = collectd,pg_catalog;

-- pg_stat_activity

create or replace function pg_stat_activity() returns setof pg_catalog.pg_stat_activity as $$begin return query(select * from pg_catalog.pg_stat_activity); end$$ language plpgsql security definer;
revoke all on function pg_stat_activity() from public;
grant execute on function pg_stat_activity() to collectd;

create view pg_stat_activity as select * from pg_stat_activity();
revoke all on collectd.pg_stat_activity from public;
grant select on pg_stat_activity to collectd;
