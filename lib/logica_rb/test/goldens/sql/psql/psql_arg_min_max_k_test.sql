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
-- Logica type: logicarecord462007516
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord462007516') then create type logicarecord462007516 as (argpod text); end if;
-- Logica type: logicarecord183863755
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord183863755') then create type logicarecord183863755 as (arg text, value numeric); end if;
-- Logica type: logicarecord388208798
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord388208798') then create type logicarecord388208798 as (payload text, v numeric); end if;
-- Logica type: logicarecord68214556
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord68214556') then create type logicarecord68214556 as (arg logicarecord462007516, value numeric); end if;
-- Logica type: logicarecord843555759
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord843555759') then create type logicarecord843555759 as (arg logicarecord388208798, value numeric); end if;
-- Logica type: logicarecord540637728
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord540637728') then create type logicarecord540637728 as (arg logicarecord388208798, lim numeric, value numeric); end if;
END $$;
WITH t_2_Data AS (SELECT * FROM (
  
    SELECT
      10 AS v,
      'a' AS payload UNION ALL
  
    SELECT
      5 AS v,
      'b' AS payload UNION ALL
  
    SELECT
      20 AS v,
      'c' AS payload UNION ALL
  
    SELECT
      100 AS v,
      'd' AS payload UNION ALL
  
    SELECT
      30 AS v,
      'e' AS payload UNION ALL
  
    SELECT
      15 AS v,
      'f' AS payload
) AS UNUSED_TABLE_NAME  ),
t_0_TestArgMax AS (SELECT
  ((ARRAY_AGG(ROW(Data.payload)::logicarecord462007516 order by Data.v desc))[1]).argpod AS logica_value
FROM
  t_2_Data AS Data),
t_3_TestArgMaxK AS (SELECT
  (ARRAY_AGG(ROW(t_4_Data.payload, t_4_Data.v)::logicarecord388208798 order by t_4_Data.v desc))[1:3] AS logica_value
FROM
  t_2_Data AS t_4_Data),
t_6_TestArgMin AS (SELECT
  ((ARRAY_AGG(ROW(t_7_Data.payload)::logicarecord462007516 order by t_7_Data.v))[1]).argpod AS logica_value
FROM
  t_2_Data AS t_7_Data),
t_9_TestArgMinK AS (SELECT
  (ARRAY_AGG(ROW(t_10_Data.payload, t_10_Data.v)::logicarecord388208798 order by t_10_Data.v))[1:2] AS logica_value
FROM
  t_2_Data AS t_10_Data)
SELECT * FROM (
  
    SELECT
      'Max' AS opt,
      TestArgMax.logica_value AS arg_opt,
      TestArgMaxK.logica_value AS arg_opt_k
    FROM
      t_0_TestArgMax AS TestArgMax, t_3_TestArgMaxK AS TestArgMaxK UNION ALL
  
    SELECT
      'Min' AS opt,
      TestArgMin.logica_value AS arg_opt,
      TestArgMinK.logica_value AS arg_opt_k
    FROM
      t_6_TestArgMin AS TestArgMin, t_9_TestArgMinK AS TestArgMinK
) AS UNUSED_TABLE_NAME  ORDER BY arg_opt ;
