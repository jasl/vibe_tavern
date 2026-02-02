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
-- Logica type: logicarecord988402559
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord988402559') then create type logicarecord988402559 as (e text); end if;
-- Logica type: logicarecord897399178
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord897399178') then create type logicarecord897399178 as (a numeric, b text); end if;
-- Logica type: logicarecord607780065
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord607780065') then create type logicarecord607780065 as (c numeric, d logicarecord988402559[]); end if;
-- Logica type: logicarecord597750424
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord597750424') then create type logicarecord597750424 as (arg numeric, value logicarecord897399178); end if;
-- Logica type: logicarecord964904363
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord964904363') then create type logicarecord964904363 as (f logicarecord607780065, g text); end if;
END $$;


DROP TABLE IF EXISTS logica_home.T CASCADE;
CREATE TABLE logica_home.T AS SELECT * FROM (
  
    SELECT
      1 AS a,
      'I' AS b UNION ALL
  
    SELECT
      2 AS a,
      'II' AS b UNION ALL
  
    SELECT
      3 AS a,
      'III' AS b
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.T

DROP TABLE IF EXISTS logica_home.R CASCADE;
CREATE TABLE logica_home.R AS SELECT
  ROW(5, ARRAY[ROW('e')::logicarecord988402559]::logicarecord988402559[])::logicarecord607780065 AS f,
  'g' AS g;

-- Interacting with table logica_home.R

DROP TABLE IF EXISTS logica_home.PrepareData CASCADE;
CREATE TABLE logica_home.PrepareData AS WITH t_2_SaveT AS (SELECT
  SUM(1) AS logica_value
FROM
  logica_home.T AS T),
t_3_SaveR AS (SELECT
  SUM(1) AS logica_value
FROM
  logica_home.R AS R),
t_1_PrepareData_MultBodyAggAux AS (SELECT * FROM (
  
    SELECT
      'done' AS col0,
      1 AS logica_value
    FROM
      t_2_SaveT AS SaveT UNION ALL
  
    SELECT
      'done' AS col0,
      1 AS logica_value
    FROM
      t_3_SaveR AS SaveR
) AS UNUSED_TABLE_NAME  )
SELECT
  PrepareData_MultBodyAggAux.col0 AS col0,
  SUM(PrepareData_MultBodyAggAux.logica_value) AS logica_value
FROM
  t_1_PrepareData_MultBodyAggAux AS PrepareData_MultBodyAggAux
GROUP BY PrepareData_MultBodyAggAux.col0;

-- Interacting with table logica_home.PrepareData

-- Interacting with table logica_home.T

-- Interacting with table logica_home.R

SELECT
  ROW((RawE).f, (RawE).g)::logicarecord964904363 AS col0,
  ARRAY_AGG(ROW(D.a, D.b)::logicarecord897399178 order by D.a) AS logica_value
FROM
  logica_home.PrepareData AS PrepareData, logica_home.T AS D, logica_home.R AS RawE
GROUP BY ROW((RawE).f, (RawE).g)::logicarecord964904363;
