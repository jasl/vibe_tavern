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
-- Logica type: logicarecord944799139
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord944799139') then create type logicarecord944799139 as (o numeric); end if;
-- Logica type: logicarecord574638620
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord574638620') then create type logicarecord574638620 as (z numeric); end if;
-- Logica type: logicarecord350574256
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord350574256') then create type logicarecord350574256 as (a logicarecord574638620); end if;
END $$;
SELECT
  CAST((SELECT
  ARRAY_AGG((CASE WHEN x_5 = 0 THEN ROW(x_4)::logicarecord350574256 ELSE NULL END)) AS logica_value
FROM
  UNNEST(ARRAY[ROW(1)::logicarecord574638620]::logicarecord574638620[]) as x_4, UNNEST(ARRAY[0]::numeric[]) as x_5) AS logicarecord350574256[]) AS col0,
  ROW(1)::logicarecord944799139 AS col1;
