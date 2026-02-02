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
-- Logica type: logicarecord884343024
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord884343024') then create type logicarecord884343024 as (arg numeric, value numeric); end if;
-- Logica type: logicarecord321788516
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord321788516') then create type logicarecord321788516 as (arg numeric, lim numeric, value numeric); end if;
END $$;
SELECT
  CAST((SELECT
  (ARRAY_AGG(((CASE WHEN x_8 = 0 THEN ROW(x_7, x_7)::logicarecord884343024 ELSE NULL END)).arg order by ((CASE WHEN x_8 = 0 THEN ROW(x_7, x_7)::logicarecord884343024 ELSE NULL END)).value desc))[1:2] AS logica_value
FROM
  UNNEST(ARRAY[x_2]::numeric[]) as x_7, UNNEST(ARRAY[0]::numeric[]) as x_8) AS numeric[]) AS col0
FROM
  UNNEST(ARRAY[1, 2]::numeric[]) as x_2;
