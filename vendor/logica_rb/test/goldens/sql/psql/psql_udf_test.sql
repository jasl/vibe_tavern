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
-- Logica type: logicarecord558669504
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord558669504') then create type logicarecord558669504 as (a numeric, b numeric); end if;
END $$;


DROP FUNCTION IF EXISTS S CASCADE; CREATE OR REPLACE FUNCTION S(a text, b text) RETURNS text AS $$ select (CASE WHEN (a IS null) THEN b ELSE (((('(' || a) || ':') || b) || ')') END) $$ language sql;

CREATE AGGREGATE BareA (text) (   sfunc = S,   stype = text);

DROP FUNCTION IF EXISTS F CASCADE; CREATE OR REPLACE FUNCTION F(x numeric) RETURNS numeric AS $$ select (((2) * (x))) $$ language sql;

DROP FUNCTION IF EXISTS G CASCADE; CREATE OR REPLACE FUNCTION G(x numeric, y numeric) RETURNS logicarecord558669504[] AS $$ select (CAST((SELECT
  ARRAY_AGG((CASE WHEN x_8 = 0 THEN ROW(((x) * (y)), x_7)::logicarecord558669504 ELSE NULL END)) AS logica_value
FROM
  UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, ((y) + (1)) - 1) as x)) as x_7, UNNEST(ARRAY[0]::numeric[]) as x_8) AS logicarecord558669504[])) $$ language sql;

SELECT
  x_3 AS col0,
  x_4 AS col1,
  F(x_3) AS col2,
  G(x_3, x_4) AS col3,
  CAST((SELECT
  BareA((CASE WHEN x_9 = 0 THEN x_8 ELSE NULL END)) AS logica_value
FROM
  UNNEST(ARRAY[CAST(x_3 AS TEXT), 'a', 'b', 'c', CAST(x_4 AS TEXT)]::text[]) as x_8, UNNEST(ARRAY[0]::numeric[]) as x_9) AS text) AS col4
FROM
  UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 3 - 1) as x)) as x_3, UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 4 - 1) as x)) as x_4 ORDER BY col0, col1;
