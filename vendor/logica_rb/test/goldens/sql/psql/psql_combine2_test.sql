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
-- Logica type: logicarecord574638620
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord574638620') then create type logicarecord574638620 as (z numeric); end if;
-- Logica type: logicarecord674758041
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord674758041') then create type logicarecord674758041 as (r numeric, t numeric); end if;
-- Logica type: logicarecord814314113
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord814314113') then create type logicarecord814314113 as (a numeric, dr numeric); end if;
-- Logica type: logicarecord808675462
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord808675462') then create type logicarecord808675462 as (b numeric, c logicarecord574638620[]); end if;
END $$;
WITH t_0_T AS (SELECT * FROM (
  
    SELECT
      ROW(3, 1)::logicarecord674758041 AS col0 UNION ALL
  
    SELECT
      ROW(4, 2)::logicarecord674758041 AS col0
) AS UNUSED_TABLE_NAME  )
SELECT
  ROW(1, ((2) * ((T.col0).r)))::logicarecord814314113 AS col0,
  ROW(2, CAST((SELECT
  ARRAY_AGG((CASE WHEN x_4 = 0 THEN ROW(((((2) * (x_3))) + ((T.col0).t)))::logicarecord574638620 ELSE NULL END)) AS logica_value
FROM
  UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 3 - 1) as x)) as x_3, UNNEST(ARRAY[0]::numeric[]) as x_4) AS logicarecord574638620[]))::logicarecord808675462 AS logica_value
FROM
  t_0_T AS T
WHERE
  (T.col0 = ROW((T.col0).r, (T.col0).t)::logicarecord674758041);
