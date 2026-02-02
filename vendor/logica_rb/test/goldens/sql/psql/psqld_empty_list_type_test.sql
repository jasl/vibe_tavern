-- Initializing PostgreSQL environment.
set client_min_messages to warning;
create schema if not exists logica_home;
-- Empty logica type: logicarecord893574736;
DO $$ BEGIN if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord893574736') then create type logicarecord893574736 as (nirvana numeric); end if; END $$;


DO $$
BEGIN
-- Logica type: logicarecord481217614
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord481217614') then create type logicarecord481217614 as (r logicarecord893574736); end if;
-- Logica type: logicarecord86796764
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord86796764') then create type logicarecord86796764 as (s text); end if;
-- Logica type: logicarecord435113620
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord435113620') then create type logicarecord435113620 as (f numeric); end if;
END $$;


DROP TABLE IF EXISTS logica_home.T CASCADE;
CREATE TABLE logica_home.T AS SELECT
  ARRAY[]::logicarecord435113620[] AS logica_value
FROM
  (SELECT 'singleton' as s) as unused_singleton;

-- Interacting with table logica_home.T

WITH t_0_Q AS (SELECT
  SUM((x_4).f) AS logica_value
FROM
  logica_home.T AS T, UNNEST(T.logica_value) as x_4)
SELECT
  Q.logica_value AS logica_value
FROM
  t_0_Q AS Q;
