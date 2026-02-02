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
-- Logica type: logicarecord751083768
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord751083768') then create type logicarecord751083768 as (argpod numeric[]); end if;
-- Logica type: logicarecord559501047
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord559501047') then create type logicarecord559501047 as (arg numeric[], value numeric); end if;
-- Logica type: logicarecord227737178
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord227737178') then create type logicarecord227737178 as (arg logicarecord751083768, value numeric); end if;
END $$;
WITH t_0_T1 AS (SELECT
  ((ARRAY_AGG(ROW(ARRAY[x_9]::numeric[])::logicarecord751083768 order by (POW(((x_9) - (3)), 2))))[1]).argpod AS logica_value
FROM
  UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 10 - 1) as x)) as x_9),
t_2_T2 AS (SELECT
  ((ARRAY_AGG(ROW(ARRAY[x_21, ((x_21) + (1))]::numeric[])::logicarecord751083768 order by (POW(((x_21) - (3)), 2)) desc))[1]).argpod AS logica_value
FROM
  UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 10 - 1) as x)) as x_21)
SELECT
  T1.logica_value AS col0,
  T2.logica_value AS col1
FROM
  t_0_T1 AS T1, t_2_T2 AS T2;
