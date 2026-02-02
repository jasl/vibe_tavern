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
-- Logica type: logicarecord6083990
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord6083990') then create type logicarecord6083990 as (x numeric, y numeric); end if;
-- Logica type: logicarecord565712478
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord565712478') then create type logicarecord565712478 as (argpod logicarecord6083990[]); end if;
-- Logica type: logicarecord865112836
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord865112836') then create type logicarecord865112836 as (path logicarecord6083990[], v numeric); end if;
-- Logica type: logicarecord870775962
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord870775962') then create type logicarecord870775962 as (arg logicarecord6083990[], value numeric); end if;
-- Logica type: logicarecord134751316
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord134751316') then create type logicarecord134751316 as (arg logicarecord565712478, value numeric); end if;
END $$;


DROP TABLE IF EXISTS logica_home.G CASCADE;
CREATE TABLE logica_home.G AS WITH t_23_E AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      1 AS col1,
      3 AS logica_value UNION ALL
  
    SELECT
      1 AS col0,
      2 AS col1,
      10 AS logica_value UNION ALL
  
    SELECT
      2 AS col0,
      3 AS col1,
      3 AS logica_value UNION ALL
  
    SELECT
      0 AS col0,
      4 AS col1,
      10 AS logica_value UNION ALL
  
    SELECT
      4 AS col0,
      2 AS col1,
      10 AS logica_value UNION ALL
  
    SELECT
      1 AS col0,
      5 AS col1,
      10 AS logica_value UNION ALL
  
    SELECT
      5 AS col0,
      3 AS col1,
      10 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_21_G_MultBodyAggAux AS (SELECT * FROM (
  
    SELECT
      E.col0 AS col0,
      E.col1 AS col1,
      E.logica_value AS logica_value
    FROM
      t_23_E AS E UNION ALL
  
    SELECT
      t_25_E.col1 AS col0,
      t_25_E.col0 AS col1,
      t_25_E.logica_value AS logica_value
    FROM
      t_23_E AS t_25_E
) AS UNUSED_TABLE_NAME  )
SELECT
  G_MultBodyAggAux.col0 AS col0,
  G_MultBodyAggAux.col1 AS col1,
  SUM(G_MultBodyAggAux.logica_value) AS logica_value
FROM
  t_21_G_MultBodyAggAux AS G_MultBodyAggAux
GROUP BY G_MultBodyAggAux.col0, G_MultBodyAggAux.col1;

-- Interacting with table logica_home.G

DROP TABLE IF EXISTS logica_home.Flow_fr0 CASCADE;
CREATE TABLE logica_home.Flow_fr0 AS WITH t_20_Flow_MultBodyAggAux_f3 AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS G
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f3.col0 AS col0,
  Flow_MultBodyAggAux_f3.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f3.logica_value) AS logica_value
FROM
  t_20_Flow_MultBodyAggAux_f3 AS Flow_MultBodyAggAux_f3
GROUP BY Flow_MultBodyAggAux_f3.col0, Flow_MultBodyAggAux_f3.col1;

-- Interacting with table logica_home.Flow_fr0

DROP TABLE IF EXISTS logica_home.ActivePath_fr0 CASCADE;
CREATE TABLE logica_home.ActivePath_fr0 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr0

DROP TABLE IF EXISTS logica_home.Opportunity_fr0 CASCADE;
CREATE TABLE logica_home.Opportunity_fr0 AS WITH t_38_Opportunity_MultBodyAggAux_f4 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f4.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f4.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f4.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f4.logica_value) AS logica_value
FROM
  t_38_Opportunity_MultBodyAggAux_f4 AS Opportunity_MultBodyAggAux_f4
GROUP BY Opportunity_MultBodyAggAux_f4.col0;

-- Interacting with table logica_home.Opportunity_fr0

DROP TABLE IF EXISTS logica_home.Flow_fr1 CASCADE;
CREATE TABLE logica_home.Flow_fr1 AS WITH t_19_Flow_MultBodyAggAux_f9 AS (SELECT * FROM (
  
    SELECT
      Flow_fr0.col0 AS col0,
      Flow_fr0.col1 AS col1,
      Flow_fr0.logica_value AS logica_value
    FROM
      logica_home.Flow_fr0 AS Flow_fr0 UNION ALL
  
    SELECT
      t_30_G.col0 AS col0,
      t_30_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_30_G UNION ALL
  
    SELECT
      (x_323).x AS col0,
      (x_323).y AS col1,
      (ActivePath_fr0.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr0 AS ActivePath_fr0, UNNEST((ActivePath_fr0.logica_value).path) as x_323
    WHERE
      ((ActivePath_fr0.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_357 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr0 AS Opportunity_fr0, UNNEST(ARRAY[0]::numeric[]) as x_357
      WHERE
        (Opportunity_fr0.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr0.logica_value = ROW((ActivePath_fr0.logica_value).path, (ActivePath_fr0.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f9.col0 AS col0,
  Flow_MultBodyAggAux_f9.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f9.logica_value) AS logica_value
FROM
  t_19_Flow_MultBodyAggAux_f9 AS Flow_MultBodyAggAux_f9
GROUP BY Flow_MultBodyAggAux_f9.col0, Flow_MultBodyAggAux_f9.col1;

-- Interacting with table logica_home.Flow_fr1

DROP TABLE IF EXISTS logica_home.ActivePath_fr1 CASCADE;
CREATE TABLE logica_home.ActivePath_fr1 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_52_Opportunity_fr0.path, t_52_Opportunity_fr0.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr0 AS t_52_Opportunity_fr0
    WHERE
      (t_52_Opportunity_fr0.logica_value > 0) AND
      (3 = t_52_Opportunity_fr0.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr1

DROP TABLE IF EXISTS logica_home.Capacity_fr0 CASCADE;
CREATE TABLE logica_home.Capacity_fr0 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr0

DROP TABLE IF EXISTS logica_home.Opportunity_fr1 CASCADE;
CREATE TABLE logica_home.Opportunity_fr1 AS WITH t_55_Opportunity_MultBodyAggAux_f5 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr0.col1 AS col0,
      ROW((t_60_Opportunity_fr0.path || ARRAY[ROW(t_60_Opportunity_fr0.col0, Capacity_fr0.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_60_Opportunity_fr0.logica_value, Capacity_fr0.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_60_Opportunity_fr0.logica_value, Capacity_fr0.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr0 AS t_60_Opportunity_fr0, logica_home.Capacity_fr0 AS Capacity_fr0
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_521 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr0 AS t_67_ActivePath_fr0, UNNEST(ARRAY[0]::numeric[]) as x_521) AS numeric) IS NULL) AND
      (Capacity_fr0.col0 = t_60_Opportunity_fr0.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f5.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f5.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f5.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f5.logica_value) AS logica_value
FROM
  t_55_Opportunity_MultBodyAggAux_f5 AS Opportunity_MultBodyAggAux_f5
GROUP BY Opportunity_MultBodyAggAux_f5.col0;

-- Interacting with table logica_home.Opportunity_fr1

DROP TABLE IF EXISTS logica_home.Flow_fr2 CASCADE;
CREATE TABLE logica_home.Flow_fr2 AS WITH t_18_Flow_MultBodyAggAux_f10 AS (SELECT * FROM (
  
    SELECT
      Flow_fr1.col0 AS col0,
      Flow_fr1.col1 AS col1,
      Flow_fr1.logica_value AS logica_value
    FROM
      logica_home.Flow_fr1 AS Flow_fr1 UNION ALL
  
    SELECT
      t_45_G.col0 AS col0,
      t_45_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_45_G UNION ALL
  
    SELECT
      (x_417).x AS col0,
      (x_417).y AS col1,
      (ActivePath_fr1.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr1 AS ActivePath_fr1, UNNEST((ActivePath_fr1.logica_value).path) as x_417
    WHERE
      ((ActivePath_fr1.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_451 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr1 AS Opportunity_fr1, UNNEST(ARRAY[0]::numeric[]) as x_451
      WHERE
        (Opportunity_fr1.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr1.logica_value = ROW((ActivePath_fr1.logica_value).path, (ActivePath_fr1.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f10.col0 AS col0,
  Flow_MultBodyAggAux_f10.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f10.logica_value) AS logica_value
FROM
  t_18_Flow_MultBodyAggAux_f10 AS Flow_MultBodyAggAux_f10
GROUP BY Flow_MultBodyAggAux_f10.col0, Flow_MultBodyAggAux_f10.col1;

-- Interacting with table logica_home.Flow_fr2

DROP TABLE IF EXISTS logica_home.ActivePath_fr2 CASCADE;
CREATE TABLE logica_home.ActivePath_fr2 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_75_Opportunity_fr1.path, t_75_Opportunity_fr1.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr1 AS t_75_Opportunity_fr1
    WHERE
      (t_75_Opportunity_fr1.logica_value > 0) AND
      (3 = t_75_Opportunity_fr1.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr2

DROP TABLE IF EXISTS logica_home.Capacity_fr1 CASCADE;
CREATE TABLE logica_home.Capacity_fr1 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_87_G.col0 AS col0,
      t_87_G.col1 AS col1,
      ((((t_87_G.logica_value) - (t_88_Flow_fr0.logica_value))) + (t_89_Flow_fr0.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_87_G, logica_home.Flow_fr0 AS t_88_Flow_fr0, logica_home.Flow_fr0 AS t_89_Flow_fr0
    WHERE
      (t_88_Flow_fr0.col0 = t_87_G.col0) AND
      (t_88_Flow_fr0.col1 = t_87_G.col1) AND
      (t_89_Flow_fr0.col0 = t_87_G.col1) AND
      (t_89_Flow_fr0.col1 = t_87_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr1

DROP TABLE IF EXISTS logica_home.Opportunity_fr2 CASCADE;
CREATE TABLE logica_home.Opportunity_fr2 AS WITH t_78_Opportunity_MultBodyAggAux_f11 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr1.col1 AS col0,
      ROW((t_83_Opportunity_fr1.path || ARRAY[ROW(t_83_Opportunity_fr1.col0, Capacity_fr1.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_83_Opportunity_fr1.logica_value, Capacity_fr1.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_83_Opportunity_fr1.logica_value, Capacity_fr1.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr1 AS t_83_Opportunity_fr1, logica_home.Capacity_fr1 AS Capacity_fr1
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_636 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr1 AS t_90_ActivePath_fr1, UNNEST(ARRAY[0]::numeric[]) as x_636) AS numeric) IS NULL) AND
      (Capacity_fr1.col0 = t_83_Opportunity_fr1.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f11.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f11.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f11.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f11.logica_value) AS logica_value
FROM
  t_78_Opportunity_MultBodyAggAux_f11 AS Opportunity_MultBodyAggAux_f11
GROUP BY Opportunity_MultBodyAggAux_f11.col0;

-- Interacting with table logica_home.Opportunity_fr2

DROP TABLE IF EXISTS logica_home.Flow_fr3 CASCADE;
CREATE TABLE logica_home.Flow_fr3 AS WITH t_17_Flow_MultBodyAggAux_f15 AS (SELECT * FROM (
  
    SELECT
      Flow_fr2.col0 AS col0,
      Flow_fr2.col1 AS col1,
      Flow_fr2.logica_value AS logica_value
    FROM
      logica_home.Flow_fr2 AS Flow_fr2 UNION ALL
  
    SELECT
      t_68_G.col0 AS col0,
      t_68_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_68_G UNION ALL
  
    SELECT
      (x_532).x AS col0,
      (x_532).y AS col1,
      (ActivePath_fr2.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr2 AS ActivePath_fr2, UNNEST((ActivePath_fr2.logica_value).path) as x_532
    WHERE
      ((ActivePath_fr2.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_566 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr2 AS Opportunity_fr2, UNNEST(ARRAY[0]::numeric[]) as x_566
      WHERE
        (Opportunity_fr2.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr2.logica_value = ROW((ActivePath_fr2.logica_value).path, (ActivePath_fr2.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f15.col0 AS col0,
  Flow_MultBodyAggAux_f15.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f15.logica_value) AS logica_value
FROM
  t_17_Flow_MultBodyAggAux_f15 AS Flow_MultBodyAggAux_f15
GROUP BY Flow_MultBodyAggAux_f15.col0, Flow_MultBodyAggAux_f15.col1;

-- Interacting with table logica_home.Flow_fr3

DROP TABLE IF EXISTS logica_home.ActivePath_fr3 CASCADE;
CREATE TABLE logica_home.ActivePath_fr3 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_98_Opportunity_fr2.path, t_98_Opportunity_fr2.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr2 AS t_98_Opportunity_fr2
    WHERE
      (t_98_Opportunity_fr2.logica_value > 0) AND
      (3 = t_98_Opportunity_fr2.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr3

DROP TABLE IF EXISTS logica_home.Capacity_fr2 CASCADE;
CREATE TABLE logica_home.Capacity_fr2 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_110_G.col0 AS col0,
      t_110_G.col1 AS col1,
      ((((t_110_G.logica_value) - (t_111_Flow_fr1.logica_value))) + (t_112_Flow_fr1.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_110_G, logica_home.Flow_fr1 AS t_111_Flow_fr1, logica_home.Flow_fr1 AS t_112_Flow_fr1
    WHERE
      (t_111_Flow_fr1.col0 = t_110_G.col0) AND
      (t_111_Flow_fr1.col1 = t_110_G.col1) AND
      (t_112_Flow_fr1.col0 = t_110_G.col1) AND
      (t_112_Flow_fr1.col1 = t_110_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr2

DROP TABLE IF EXISTS logica_home.Opportunity_fr3 CASCADE;
CREATE TABLE logica_home.Opportunity_fr3 AS WITH t_101_Opportunity_MultBodyAggAux_f16 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr2.col1 AS col0,
      ROW((t_106_Opportunity_fr2.path || ARRAY[ROW(t_106_Opportunity_fr2.col0, Capacity_fr2.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_106_Opportunity_fr2.logica_value, Capacity_fr2.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_106_Opportunity_fr2.logica_value, Capacity_fr2.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr2 AS t_106_Opportunity_fr2, logica_home.Capacity_fr2 AS Capacity_fr2
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_751 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr2 AS t_113_ActivePath_fr2, UNNEST(ARRAY[0]::numeric[]) as x_751) AS numeric) IS NULL) AND
      (Capacity_fr2.col0 = t_106_Opportunity_fr2.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f16.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f16.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f16.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f16.logica_value) AS logica_value
FROM
  t_101_Opportunity_MultBodyAggAux_f16 AS Opportunity_MultBodyAggAux_f16
GROUP BY Opportunity_MultBodyAggAux_f16.col0;

-- Interacting with table logica_home.Opportunity_fr3

DROP TABLE IF EXISTS logica_home.Flow_fr4 CASCADE;
CREATE TABLE logica_home.Flow_fr4 AS WITH t_16_Flow_MultBodyAggAux_f21 AS (SELECT * FROM (
  
    SELECT
      Flow_fr3.col0 AS col0,
      Flow_fr3.col1 AS col1,
      Flow_fr3.logica_value AS logica_value
    FROM
      logica_home.Flow_fr3 AS Flow_fr3 UNION ALL
  
    SELECT
      t_91_G.col0 AS col0,
      t_91_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_91_G UNION ALL
  
    SELECT
      (x_647).x AS col0,
      (x_647).y AS col1,
      (ActivePath_fr3.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr3 AS ActivePath_fr3, UNNEST((ActivePath_fr3.logica_value).path) as x_647
    WHERE
      ((ActivePath_fr3.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_681 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr3 AS Opportunity_fr3, UNNEST(ARRAY[0]::numeric[]) as x_681
      WHERE
        (Opportunity_fr3.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr3.logica_value = ROW((ActivePath_fr3.logica_value).path, (ActivePath_fr3.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f21.col0 AS col0,
  Flow_MultBodyAggAux_f21.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f21.logica_value) AS logica_value
FROM
  t_16_Flow_MultBodyAggAux_f21 AS Flow_MultBodyAggAux_f21
GROUP BY Flow_MultBodyAggAux_f21.col0, Flow_MultBodyAggAux_f21.col1;

-- Interacting with table logica_home.Flow_fr4

DROP TABLE IF EXISTS logica_home.ActivePath_fr4 CASCADE;
CREATE TABLE logica_home.ActivePath_fr4 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_121_Opportunity_fr3.path, t_121_Opportunity_fr3.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr3 AS t_121_Opportunity_fr3
    WHERE
      (t_121_Opportunity_fr3.logica_value > 0) AND
      (3 = t_121_Opportunity_fr3.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr4

DROP TABLE IF EXISTS logica_home.Capacity_fr3 CASCADE;
CREATE TABLE logica_home.Capacity_fr3 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_133_G.col0 AS col0,
      t_133_G.col1 AS col1,
      ((((t_133_G.logica_value) - (t_134_Flow_fr2.logica_value))) + (t_135_Flow_fr2.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_133_G, logica_home.Flow_fr2 AS t_134_Flow_fr2, logica_home.Flow_fr2 AS t_135_Flow_fr2
    WHERE
      (t_134_Flow_fr2.col0 = t_133_G.col0) AND
      (t_134_Flow_fr2.col1 = t_133_G.col1) AND
      (t_135_Flow_fr2.col0 = t_133_G.col1) AND
      (t_135_Flow_fr2.col1 = t_133_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr3

DROP TABLE IF EXISTS logica_home.Opportunity_fr4 CASCADE;
CREATE TABLE logica_home.Opportunity_fr4 AS WITH t_124_Opportunity_MultBodyAggAux_f17 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr3.col1 AS col0,
      ROW((t_129_Opportunity_fr3.path || ARRAY[ROW(t_129_Opportunity_fr3.col0, Capacity_fr3.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_129_Opportunity_fr3.logica_value, Capacity_fr3.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_129_Opportunity_fr3.logica_value, Capacity_fr3.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr3 AS t_129_Opportunity_fr3, logica_home.Capacity_fr3 AS Capacity_fr3
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_866 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr3 AS t_136_ActivePath_fr3, UNNEST(ARRAY[0]::numeric[]) as x_866) AS numeric) IS NULL) AND
      (Capacity_fr3.col0 = t_129_Opportunity_fr3.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f17.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f17.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f17.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f17.logica_value) AS logica_value
FROM
  t_124_Opportunity_MultBodyAggAux_f17 AS Opportunity_MultBodyAggAux_f17
GROUP BY Opportunity_MultBodyAggAux_f17.col0;

-- Interacting with table logica_home.Opportunity_fr4

DROP TABLE IF EXISTS logica_home.Flow_fr5 CASCADE;
CREATE TABLE logica_home.Flow_fr5 AS WITH t_15_Flow_MultBodyAggAux_f22 AS (SELECT * FROM (
  
    SELECT
      Flow_fr4.col0 AS col0,
      Flow_fr4.col1 AS col1,
      Flow_fr4.logica_value AS logica_value
    FROM
      logica_home.Flow_fr4 AS Flow_fr4 UNION ALL
  
    SELECT
      t_114_G.col0 AS col0,
      t_114_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_114_G UNION ALL
  
    SELECT
      (x_762).x AS col0,
      (x_762).y AS col1,
      (ActivePath_fr4.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr4 AS ActivePath_fr4, UNNEST((ActivePath_fr4.logica_value).path) as x_762
    WHERE
      ((ActivePath_fr4.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_796 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr4 AS Opportunity_fr4, UNNEST(ARRAY[0]::numeric[]) as x_796
      WHERE
        (Opportunity_fr4.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr4.logica_value = ROW((ActivePath_fr4.logica_value).path, (ActivePath_fr4.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f22.col0 AS col0,
  Flow_MultBodyAggAux_f22.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f22.logica_value) AS logica_value
FROM
  t_15_Flow_MultBodyAggAux_f22 AS Flow_MultBodyAggAux_f22
GROUP BY Flow_MultBodyAggAux_f22.col0, Flow_MultBodyAggAux_f22.col1;

-- Interacting with table logica_home.Flow_fr5

DROP TABLE IF EXISTS logica_home.ActivePath_fr5 CASCADE;
CREATE TABLE logica_home.ActivePath_fr5 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_144_Opportunity_fr4.path, t_144_Opportunity_fr4.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr4 AS t_144_Opportunity_fr4
    WHERE
      (t_144_Opportunity_fr4.logica_value > 0) AND
      (3 = t_144_Opportunity_fr4.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr5

DROP TABLE IF EXISTS logica_home.Capacity_fr4 CASCADE;
CREATE TABLE logica_home.Capacity_fr4 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_156_G.col0 AS col0,
      t_156_G.col1 AS col1,
      ((((t_156_G.logica_value) - (t_157_Flow_fr3.logica_value))) + (t_158_Flow_fr3.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_156_G, logica_home.Flow_fr3 AS t_157_Flow_fr3, logica_home.Flow_fr3 AS t_158_Flow_fr3
    WHERE
      (t_157_Flow_fr3.col0 = t_156_G.col0) AND
      (t_157_Flow_fr3.col1 = t_156_G.col1) AND
      (t_158_Flow_fr3.col0 = t_156_G.col1) AND
      (t_158_Flow_fr3.col1 = t_156_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr4

DROP TABLE IF EXISTS logica_home.Opportunity_fr5 CASCADE;
CREATE TABLE logica_home.Opportunity_fr5 AS WITH t_147_Opportunity_MultBodyAggAux_f23 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr4.col1 AS col0,
      ROW((t_152_Opportunity_fr4.path || ARRAY[ROW(t_152_Opportunity_fr4.col0, Capacity_fr4.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_152_Opportunity_fr4.logica_value, Capacity_fr4.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_152_Opportunity_fr4.logica_value, Capacity_fr4.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr4 AS t_152_Opportunity_fr4, logica_home.Capacity_fr4 AS Capacity_fr4
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_981 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr4 AS t_159_ActivePath_fr4, UNNEST(ARRAY[0]::numeric[]) as x_981) AS numeric) IS NULL) AND
      (Capacity_fr4.col0 = t_152_Opportunity_fr4.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f23.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f23.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f23.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f23.logica_value) AS logica_value
FROM
  t_147_Opportunity_MultBodyAggAux_f23 AS Opportunity_MultBodyAggAux_f23
GROUP BY Opportunity_MultBodyAggAux_f23.col0;

-- Interacting with table logica_home.Opportunity_fr5

DROP TABLE IF EXISTS logica_home.Flow_fr6 CASCADE;
CREATE TABLE logica_home.Flow_fr6 AS WITH t_14_Flow_MultBodyAggAux_f27 AS (SELECT * FROM (
  
    SELECT
      Flow_fr5.col0 AS col0,
      Flow_fr5.col1 AS col1,
      Flow_fr5.logica_value AS logica_value
    FROM
      logica_home.Flow_fr5 AS Flow_fr5 UNION ALL
  
    SELECT
      t_137_G.col0 AS col0,
      t_137_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_137_G UNION ALL
  
    SELECT
      (x_877).x AS col0,
      (x_877).y AS col1,
      (ActivePath_fr5.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr5 AS ActivePath_fr5, UNNEST((ActivePath_fr5.logica_value).path) as x_877
    WHERE
      ((ActivePath_fr5.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_911 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr5 AS Opportunity_fr5, UNNEST(ARRAY[0]::numeric[]) as x_911
      WHERE
        (Opportunity_fr5.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr5.logica_value = ROW((ActivePath_fr5.logica_value).path, (ActivePath_fr5.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f27.col0 AS col0,
  Flow_MultBodyAggAux_f27.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f27.logica_value) AS logica_value
FROM
  t_14_Flow_MultBodyAggAux_f27 AS Flow_MultBodyAggAux_f27
GROUP BY Flow_MultBodyAggAux_f27.col0, Flow_MultBodyAggAux_f27.col1;

-- Interacting with table logica_home.Flow_fr6

DROP TABLE IF EXISTS logica_home.ActivePath_fr6 CASCADE;
CREATE TABLE logica_home.ActivePath_fr6 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_167_Opportunity_fr5.path, t_167_Opportunity_fr5.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr5 AS t_167_Opportunity_fr5
    WHERE
      (t_167_Opportunity_fr5.logica_value > 0) AND
      (3 = t_167_Opportunity_fr5.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr6

DROP TABLE IF EXISTS logica_home.Capacity_fr5 CASCADE;
CREATE TABLE logica_home.Capacity_fr5 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_179_G.col0 AS col0,
      t_179_G.col1 AS col1,
      ((((t_179_G.logica_value) - (t_180_Flow_fr4.logica_value))) + (t_181_Flow_fr4.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_179_G, logica_home.Flow_fr4 AS t_180_Flow_fr4, logica_home.Flow_fr4 AS t_181_Flow_fr4
    WHERE
      (t_180_Flow_fr4.col0 = t_179_G.col0) AND
      (t_180_Flow_fr4.col1 = t_179_G.col1) AND
      (t_181_Flow_fr4.col0 = t_179_G.col1) AND
      (t_181_Flow_fr4.col1 = t_179_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr5

DROP TABLE IF EXISTS logica_home.Opportunity_fr6 CASCADE;
CREATE TABLE logica_home.Opportunity_fr6 AS WITH t_170_Opportunity_MultBodyAggAux_f28 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr5.col1 AS col0,
      ROW((t_175_Opportunity_fr5.path || ARRAY[ROW(t_175_Opportunity_fr5.col0, Capacity_fr5.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_175_Opportunity_fr5.logica_value, Capacity_fr5.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_175_Opportunity_fr5.logica_value, Capacity_fr5.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr5 AS t_175_Opportunity_fr5, logica_home.Capacity_fr5 AS Capacity_fr5
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_1096 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr5 AS t_182_ActivePath_fr5, UNNEST(ARRAY[0]::numeric[]) as x_1096) AS numeric) IS NULL) AND
      (Capacity_fr5.col0 = t_175_Opportunity_fr5.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f28.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f28.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f28.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f28.logica_value) AS logica_value
FROM
  t_170_Opportunity_MultBodyAggAux_f28 AS Opportunity_MultBodyAggAux_f28
GROUP BY Opportunity_MultBodyAggAux_f28.col0;

-- Interacting with table logica_home.Opportunity_fr6

DROP TABLE IF EXISTS logica_home.Flow_fr7 CASCADE;
CREATE TABLE logica_home.Flow_fr7 AS WITH t_13_Flow_MultBodyAggAux_f33 AS (SELECT * FROM (
  
    SELECT
      Flow_fr6.col0 AS col0,
      Flow_fr6.col1 AS col1,
      Flow_fr6.logica_value AS logica_value
    FROM
      logica_home.Flow_fr6 AS Flow_fr6 UNION ALL
  
    SELECT
      t_160_G.col0 AS col0,
      t_160_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_160_G UNION ALL
  
    SELECT
      (x_992).x AS col0,
      (x_992).y AS col1,
      (ActivePath_fr6.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr6 AS ActivePath_fr6, UNNEST((ActivePath_fr6.logica_value).path) as x_992
    WHERE
      ((ActivePath_fr6.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_1026 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr6 AS Opportunity_fr6, UNNEST(ARRAY[0]::numeric[]) as x_1026
      WHERE
        (Opportunity_fr6.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr6.logica_value = ROW((ActivePath_fr6.logica_value).path, (ActivePath_fr6.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f33.col0 AS col0,
  Flow_MultBodyAggAux_f33.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f33.logica_value) AS logica_value
FROM
  t_13_Flow_MultBodyAggAux_f33 AS Flow_MultBodyAggAux_f33
GROUP BY Flow_MultBodyAggAux_f33.col0, Flow_MultBodyAggAux_f33.col1;

-- Interacting with table logica_home.Flow_fr7

DROP TABLE IF EXISTS logica_home.ActivePath_fr7 CASCADE;
CREATE TABLE logica_home.ActivePath_fr7 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_190_Opportunity_fr6.path, t_190_Opportunity_fr6.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr6 AS t_190_Opportunity_fr6
    WHERE
      (t_190_Opportunity_fr6.logica_value > 0) AND
      (3 = t_190_Opportunity_fr6.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr7

DROP TABLE IF EXISTS logica_home.Capacity_fr6 CASCADE;
CREATE TABLE logica_home.Capacity_fr6 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_202_G.col0 AS col0,
      t_202_G.col1 AS col1,
      ((((t_202_G.logica_value) - (t_203_Flow_fr5.logica_value))) + (t_204_Flow_fr5.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_202_G, logica_home.Flow_fr5 AS t_203_Flow_fr5, logica_home.Flow_fr5 AS t_204_Flow_fr5
    WHERE
      (t_203_Flow_fr5.col0 = t_202_G.col0) AND
      (t_203_Flow_fr5.col1 = t_202_G.col1) AND
      (t_204_Flow_fr5.col0 = t_202_G.col1) AND
      (t_204_Flow_fr5.col1 = t_202_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr6

DROP TABLE IF EXISTS logica_home.Opportunity_fr7 CASCADE;
CREATE TABLE logica_home.Opportunity_fr7 AS WITH t_193_Opportunity_MultBodyAggAux_f29 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr6.col1 AS col0,
      ROW((t_198_Opportunity_fr6.path || ARRAY[ROW(t_198_Opportunity_fr6.col0, Capacity_fr6.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_198_Opportunity_fr6.logica_value, Capacity_fr6.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_198_Opportunity_fr6.logica_value, Capacity_fr6.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr6 AS t_198_Opportunity_fr6, logica_home.Capacity_fr6 AS Capacity_fr6
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_1211 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr6 AS t_205_ActivePath_fr6, UNNEST(ARRAY[0]::numeric[]) as x_1211) AS numeric) IS NULL) AND
      (Capacity_fr6.col0 = t_198_Opportunity_fr6.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f29.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f29.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f29.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f29.logica_value) AS logica_value
FROM
  t_193_Opportunity_MultBodyAggAux_f29 AS Opportunity_MultBodyAggAux_f29
GROUP BY Opportunity_MultBodyAggAux_f29.col0;

-- Interacting with table logica_home.Opportunity_fr7

DROP TABLE IF EXISTS logica_home.Flow_fr8 CASCADE;
CREATE TABLE logica_home.Flow_fr8 AS WITH t_12_Flow_MultBodyAggAux_f34 AS (SELECT * FROM (
  
    SELECT
      Flow_fr7.col0 AS col0,
      Flow_fr7.col1 AS col1,
      Flow_fr7.logica_value AS logica_value
    FROM
      logica_home.Flow_fr7 AS Flow_fr7 UNION ALL
  
    SELECT
      t_183_G.col0 AS col0,
      t_183_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_183_G UNION ALL
  
    SELECT
      (x_1107).x AS col0,
      (x_1107).y AS col1,
      (ActivePath_fr7.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr7 AS ActivePath_fr7, UNNEST((ActivePath_fr7.logica_value).path) as x_1107
    WHERE
      ((ActivePath_fr7.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_1141 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr7 AS Opportunity_fr7, UNNEST(ARRAY[0]::numeric[]) as x_1141
      WHERE
        (Opportunity_fr7.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr7.logica_value = ROW((ActivePath_fr7.logica_value).path, (ActivePath_fr7.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f34.col0 AS col0,
  Flow_MultBodyAggAux_f34.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f34.logica_value) AS logica_value
FROM
  t_12_Flow_MultBodyAggAux_f34 AS Flow_MultBodyAggAux_f34
GROUP BY Flow_MultBodyAggAux_f34.col0, Flow_MultBodyAggAux_f34.col1;

-- Interacting with table logica_home.Flow_fr8

DROP TABLE IF EXISTS logica_home.ActivePath_fr8 CASCADE;
CREATE TABLE logica_home.ActivePath_fr8 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_213_Opportunity_fr7.path, t_213_Opportunity_fr7.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr7 AS t_213_Opportunity_fr7
    WHERE
      (t_213_Opportunity_fr7.logica_value > 0) AND
      (3 = t_213_Opportunity_fr7.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr8

DROP TABLE IF EXISTS logica_home.Capacity_fr7 CASCADE;
CREATE TABLE logica_home.Capacity_fr7 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_225_G.col0 AS col0,
      t_225_G.col1 AS col1,
      ((((t_225_G.logica_value) - (t_226_Flow_fr6.logica_value))) + (t_227_Flow_fr6.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_225_G, logica_home.Flow_fr6 AS t_226_Flow_fr6, logica_home.Flow_fr6 AS t_227_Flow_fr6
    WHERE
      (t_226_Flow_fr6.col0 = t_225_G.col0) AND
      (t_226_Flow_fr6.col1 = t_225_G.col1) AND
      (t_227_Flow_fr6.col0 = t_225_G.col1) AND
      (t_227_Flow_fr6.col1 = t_225_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr7

DROP TABLE IF EXISTS logica_home.Opportunity_fr8 CASCADE;
CREATE TABLE logica_home.Opportunity_fr8 AS WITH t_216_Opportunity_MultBodyAggAux_f35 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr7.col1 AS col0,
      ROW((t_221_Opportunity_fr7.path || ARRAY[ROW(t_221_Opportunity_fr7.col0, Capacity_fr7.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_221_Opportunity_fr7.logica_value, Capacity_fr7.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_221_Opportunity_fr7.logica_value, Capacity_fr7.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr7 AS t_221_Opportunity_fr7, logica_home.Capacity_fr7 AS Capacity_fr7
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_1326 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr7 AS t_228_ActivePath_fr7, UNNEST(ARRAY[0]::numeric[]) as x_1326) AS numeric) IS NULL) AND
      (Capacity_fr7.col0 = t_221_Opportunity_fr7.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f35.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f35.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f35.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f35.logica_value) AS logica_value
FROM
  t_216_Opportunity_MultBodyAggAux_f35 AS Opportunity_MultBodyAggAux_f35
GROUP BY Opportunity_MultBodyAggAux_f35.col0;

-- Interacting with table logica_home.Opportunity_fr8

DROP TABLE IF EXISTS logica_home.Flow_fr9 CASCADE;
CREATE TABLE logica_home.Flow_fr9 AS WITH t_11_Flow_MultBodyAggAux_f39 AS (SELECT * FROM (
  
    SELECT
      Flow_fr8.col0 AS col0,
      Flow_fr8.col1 AS col1,
      Flow_fr8.logica_value AS logica_value
    FROM
      logica_home.Flow_fr8 AS Flow_fr8 UNION ALL
  
    SELECT
      t_206_G.col0 AS col0,
      t_206_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_206_G UNION ALL
  
    SELECT
      (x_1222).x AS col0,
      (x_1222).y AS col1,
      (ActivePath_fr8.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr8 AS ActivePath_fr8, UNNEST((ActivePath_fr8.logica_value).path) as x_1222
    WHERE
      ((ActivePath_fr8.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_1256 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr8 AS Opportunity_fr8, UNNEST(ARRAY[0]::numeric[]) as x_1256
      WHERE
        (Opportunity_fr8.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr8.logica_value = ROW((ActivePath_fr8.logica_value).path, (ActivePath_fr8.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f39.col0 AS col0,
  Flow_MultBodyAggAux_f39.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f39.logica_value) AS logica_value
FROM
  t_11_Flow_MultBodyAggAux_f39 AS Flow_MultBodyAggAux_f39
GROUP BY Flow_MultBodyAggAux_f39.col0, Flow_MultBodyAggAux_f39.col1;

-- Interacting with table logica_home.Flow_fr9

DROP TABLE IF EXISTS logica_home.ActivePath_fr9 CASCADE;
CREATE TABLE logica_home.ActivePath_fr9 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_236_Opportunity_fr8.path, t_236_Opportunity_fr8.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr8 AS t_236_Opportunity_fr8
    WHERE
      (t_236_Opportunity_fr8.logica_value > 0) AND
      (3 = t_236_Opportunity_fr8.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr9

DROP TABLE IF EXISTS logica_home.Capacity_fr8 CASCADE;
CREATE TABLE logica_home.Capacity_fr8 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_248_G.col0 AS col0,
      t_248_G.col1 AS col1,
      ((((t_248_G.logica_value) - (t_249_Flow_fr7.logica_value))) + (t_250_Flow_fr7.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_248_G, logica_home.Flow_fr7 AS t_249_Flow_fr7, logica_home.Flow_fr7 AS t_250_Flow_fr7
    WHERE
      (t_249_Flow_fr7.col0 = t_248_G.col0) AND
      (t_249_Flow_fr7.col1 = t_248_G.col1) AND
      (t_250_Flow_fr7.col0 = t_248_G.col1) AND
      (t_250_Flow_fr7.col1 = t_248_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr8

DROP TABLE IF EXISTS logica_home.Opportunity_fr9 CASCADE;
CREATE TABLE logica_home.Opportunity_fr9 AS WITH t_239_Opportunity_MultBodyAggAux_f40 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr8.col1 AS col0,
      ROW((t_244_Opportunity_fr8.path || ARRAY[ROW(t_244_Opportunity_fr8.col0, Capacity_fr8.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_244_Opportunity_fr8.logica_value, Capacity_fr8.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_244_Opportunity_fr8.logica_value, Capacity_fr8.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr8 AS t_244_Opportunity_fr8, logica_home.Capacity_fr8 AS Capacity_fr8
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_1441 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr8 AS t_251_ActivePath_fr8, UNNEST(ARRAY[0]::numeric[]) as x_1441) AS numeric) IS NULL) AND
      (Capacity_fr8.col0 = t_244_Opportunity_fr8.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f40.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f40.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f40.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f40.logica_value) AS logica_value
FROM
  t_239_Opportunity_MultBodyAggAux_f40 AS Opportunity_MultBodyAggAux_f40
GROUP BY Opportunity_MultBodyAggAux_f40.col0;

-- Interacting with table logica_home.Opportunity_fr9

DROP TABLE IF EXISTS logica_home.Flow_fr10 CASCADE;
CREATE TABLE logica_home.Flow_fr10 AS WITH t_10_Flow_MultBodyAggAux_f43 AS (SELECT * FROM (
  
    SELECT
      Flow_fr9.col0 AS col0,
      Flow_fr9.col1 AS col1,
      Flow_fr9.logica_value AS logica_value
    FROM
      logica_home.Flow_fr9 AS Flow_fr9 UNION ALL
  
    SELECT
      t_229_G.col0 AS col0,
      t_229_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_229_G UNION ALL
  
    SELECT
      (x_1337).x AS col0,
      (x_1337).y AS col1,
      (ActivePath_fr9.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr9 AS ActivePath_fr9, UNNEST((ActivePath_fr9.logica_value).path) as x_1337
    WHERE
      ((ActivePath_fr9.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_1371 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr9 AS Opportunity_fr9, UNNEST(ARRAY[0]::numeric[]) as x_1371
      WHERE
        (Opportunity_fr9.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr9.logica_value = ROW((ActivePath_fr9.logica_value).path, (ActivePath_fr9.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f43.col0 AS col0,
  Flow_MultBodyAggAux_f43.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f43.logica_value) AS logica_value
FROM
  t_10_Flow_MultBodyAggAux_f43 AS Flow_MultBodyAggAux_f43
GROUP BY Flow_MultBodyAggAux_f43.col0, Flow_MultBodyAggAux_f43.col1;

-- Interacting with table logica_home.Flow_fr10

DROP TABLE IF EXISTS logica_home.ActivePath_fr10 CASCADE;
CREATE TABLE logica_home.ActivePath_fr10 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_259_Opportunity_fr9.path, t_259_Opportunity_fr9.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr9 AS t_259_Opportunity_fr9
    WHERE
      (t_259_Opportunity_fr9.logica_value > 0) AND
      (3 = t_259_Opportunity_fr9.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr10

DROP TABLE IF EXISTS logica_home.Capacity_fr9 CASCADE;
CREATE TABLE logica_home.Capacity_fr9 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_271_G.col0 AS col0,
      t_271_G.col1 AS col1,
      ((((t_271_G.logica_value) - (t_272_Flow_fr8.logica_value))) + (t_273_Flow_fr8.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_271_G, logica_home.Flow_fr8 AS t_272_Flow_fr8, logica_home.Flow_fr8 AS t_273_Flow_fr8
    WHERE
      (t_272_Flow_fr8.col0 = t_271_G.col0) AND
      (t_272_Flow_fr8.col1 = t_271_G.col1) AND
      (t_273_Flow_fr8.col0 = t_271_G.col1) AND
      (t_273_Flow_fr8.col1 = t_271_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr9

DROP TABLE IF EXISTS logica_home.Opportunity_fr10 CASCADE;
CREATE TABLE logica_home.Opportunity_fr10 AS WITH t_262_Opportunity_MultBodyAggAux_f44 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr9.col1 AS col0,
      ROW((t_267_Opportunity_fr9.path || ARRAY[ROW(t_267_Opportunity_fr9.col0, Capacity_fr9.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_267_Opportunity_fr9.logica_value, Capacity_fr9.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_267_Opportunity_fr9.logica_value, Capacity_fr9.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr9 AS t_267_Opportunity_fr9, logica_home.Capacity_fr9 AS Capacity_fr9
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_1556 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr9 AS t_274_ActivePath_fr9, UNNEST(ARRAY[0]::numeric[]) as x_1556) AS numeric) IS NULL) AND
      (Capacity_fr9.col0 = t_267_Opportunity_fr9.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f44.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f44.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f44.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f44.logica_value) AS logica_value
FROM
  t_262_Opportunity_MultBodyAggAux_f44 AS Opportunity_MultBodyAggAux_f44
GROUP BY Opportunity_MultBodyAggAux_f44.col0;

-- Interacting with table logica_home.Opportunity_fr10

DROP TABLE IF EXISTS logica_home.Flow_fr11 CASCADE;
CREATE TABLE logica_home.Flow_fr11 AS WITH t_9_Flow_MultBodyAggAux_f49 AS (SELECT * FROM (
  
    SELECT
      Flow_fr10.col0 AS col0,
      Flow_fr10.col1 AS col1,
      Flow_fr10.logica_value AS logica_value
    FROM
      logica_home.Flow_fr10 AS Flow_fr10 UNION ALL
  
    SELECT
      t_252_G.col0 AS col0,
      t_252_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_252_G UNION ALL
  
    SELECT
      (x_1452).x AS col0,
      (x_1452).y AS col1,
      (ActivePath_fr10.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr10 AS ActivePath_fr10, UNNEST((ActivePath_fr10.logica_value).path) as x_1452
    WHERE
      ((ActivePath_fr10.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_1486 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr10 AS Opportunity_fr10, UNNEST(ARRAY[0]::numeric[]) as x_1486
      WHERE
        (Opportunity_fr10.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr10.logica_value = ROW((ActivePath_fr10.logica_value).path, (ActivePath_fr10.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f49.col0 AS col0,
  Flow_MultBodyAggAux_f49.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f49.logica_value) AS logica_value
FROM
  t_9_Flow_MultBodyAggAux_f49 AS Flow_MultBodyAggAux_f49
GROUP BY Flow_MultBodyAggAux_f49.col0, Flow_MultBodyAggAux_f49.col1;

-- Interacting with table logica_home.Flow_fr11

DROP TABLE IF EXISTS logica_home.ActivePath_fr11 CASCADE;
CREATE TABLE logica_home.ActivePath_fr11 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_282_Opportunity_fr10.path, t_282_Opportunity_fr10.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr10 AS t_282_Opportunity_fr10
    WHERE
      (t_282_Opportunity_fr10.logica_value > 0) AND
      (3 = t_282_Opportunity_fr10.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr11

DROP TABLE IF EXISTS logica_home.Capacity_fr10 CASCADE;
CREATE TABLE logica_home.Capacity_fr10 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_294_G.col0 AS col0,
      t_294_G.col1 AS col1,
      ((((t_294_G.logica_value) - (t_295_Flow_fr9.logica_value))) + (t_296_Flow_fr9.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_294_G, logica_home.Flow_fr9 AS t_295_Flow_fr9, logica_home.Flow_fr9 AS t_296_Flow_fr9
    WHERE
      (t_295_Flow_fr9.col0 = t_294_G.col0) AND
      (t_295_Flow_fr9.col1 = t_294_G.col1) AND
      (t_296_Flow_fr9.col0 = t_294_G.col1) AND
      (t_296_Flow_fr9.col1 = t_294_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr10

DROP TABLE IF EXISTS logica_home.Opportunity_fr11 CASCADE;
CREATE TABLE logica_home.Opportunity_fr11 AS WITH t_285_Opportunity_MultBodyAggAux_f45 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr10.col1 AS col0,
      ROW((t_290_Opportunity_fr10.path || ARRAY[ROW(t_290_Opportunity_fr10.col0, Capacity_fr10.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_290_Opportunity_fr10.logica_value, Capacity_fr10.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_290_Opportunity_fr10.logica_value, Capacity_fr10.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr10 AS t_290_Opportunity_fr10, logica_home.Capacity_fr10 AS Capacity_fr10
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_1671 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr10 AS t_297_ActivePath_fr10, UNNEST(ARRAY[0]::numeric[]) as x_1671) AS numeric) IS NULL) AND
      (Capacity_fr10.col0 = t_290_Opportunity_fr10.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f45.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f45.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f45.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f45.logica_value) AS logica_value
FROM
  t_285_Opportunity_MultBodyAggAux_f45 AS Opportunity_MultBodyAggAux_f45
GROUP BY Opportunity_MultBodyAggAux_f45.col0;

-- Interacting with table logica_home.Opportunity_fr11

DROP TABLE IF EXISTS logica_home.Flow_fr12 CASCADE;
CREATE TABLE logica_home.Flow_fr12 AS WITH t_8_Flow_MultBodyAggAux_f50 AS (SELECT * FROM (
  
    SELECT
      Flow_fr11.col0 AS col0,
      Flow_fr11.col1 AS col1,
      Flow_fr11.logica_value AS logica_value
    FROM
      logica_home.Flow_fr11 AS Flow_fr11 UNION ALL
  
    SELECT
      t_275_G.col0 AS col0,
      t_275_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_275_G UNION ALL
  
    SELECT
      (x_1567).x AS col0,
      (x_1567).y AS col1,
      (ActivePath_fr11.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr11 AS ActivePath_fr11, UNNEST((ActivePath_fr11.logica_value).path) as x_1567
    WHERE
      ((ActivePath_fr11.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_1601 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr11 AS Opportunity_fr11, UNNEST(ARRAY[0]::numeric[]) as x_1601
      WHERE
        (Opportunity_fr11.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr11.logica_value = ROW((ActivePath_fr11.logica_value).path, (ActivePath_fr11.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f50.col0 AS col0,
  Flow_MultBodyAggAux_f50.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f50.logica_value) AS logica_value
FROM
  t_8_Flow_MultBodyAggAux_f50 AS Flow_MultBodyAggAux_f50
GROUP BY Flow_MultBodyAggAux_f50.col0, Flow_MultBodyAggAux_f50.col1;

-- Interacting with table logica_home.Flow_fr12

DROP TABLE IF EXISTS logica_home.ActivePath_fr12 CASCADE;
CREATE TABLE logica_home.ActivePath_fr12 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_305_Opportunity_fr11.path, t_305_Opportunity_fr11.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr11 AS t_305_Opportunity_fr11
    WHERE
      (t_305_Opportunity_fr11.logica_value > 0) AND
      (3 = t_305_Opportunity_fr11.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr12

DROP TABLE IF EXISTS logica_home.Capacity_fr11 CASCADE;
CREATE TABLE logica_home.Capacity_fr11 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_317_G.col0 AS col0,
      t_317_G.col1 AS col1,
      ((((t_317_G.logica_value) - (t_318_Flow_fr10.logica_value))) + (t_319_Flow_fr10.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_317_G, logica_home.Flow_fr10 AS t_318_Flow_fr10, logica_home.Flow_fr10 AS t_319_Flow_fr10
    WHERE
      (t_318_Flow_fr10.col0 = t_317_G.col0) AND
      (t_318_Flow_fr10.col1 = t_317_G.col1) AND
      (t_319_Flow_fr10.col0 = t_317_G.col1) AND
      (t_319_Flow_fr10.col1 = t_317_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr11

DROP TABLE IF EXISTS logica_home.Opportunity_fr12 CASCADE;
CREATE TABLE logica_home.Opportunity_fr12 AS WITH t_308_Opportunity_MultBodyAggAux_f51 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr11.col1 AS col0,
      ROW((t_313_Opportunity_fr11.path || ARRAY[ROW(t_313_Opportunity_fr11.col0, Capacity_fr11.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_313_Opportunity_fr11.logica_value, Capacity_fr11.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_313_Opportunity_fr11.logica_value, Capacity_fr11.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr11 AS t_313_Opportunity_fr11, logica_home.Capacity_fr11 AS Capacity_fr11
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_1786 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr11 AS t_320_ActivePath_fr11, UNNEST(ARRAY[0]::numeric[]) as x_1786) AS numeric) IS NULL) AND
      (Capacity_fr11.col0 = t_313_Opportunity_fr11.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f51.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f51.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f51.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f51.logica_value) AS logica_value
FROM
  t_308_Opportunity_MultBodyAggAux_f51 AS Opportunity_MultBodyAggAux_f51
GROUP BY Opportunity_MultBodyAggAux_f51.col0;

-- Interacting with table logica_home.Opportunity_fr12

DROP TABLE IF EXISTS logica_home.Flow_fr13 CASCADE;
CREATE TABLE logica_home.Flow_fr13 AS WITH t_7_Flow_MultBodyAggAux_f55 AS (SELECT * FROM (
  
    SELECT
      Flow_fr12.col0 AS col0,
      Flow_fr12.col1 AS col1,
      Flow_fr12.logica_value AS logica_value
    FROM
      logica_home.Flow_fr12 AS Flow_fr12 UNION ALL
  
    SELECT
      t_298_G.col0 AS col0,
      t_298_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_298_G UNION ALL
  
    SELECT
      (x_1682).x AS col0,
      (x_1682).y AS col1,
      (ActivePath_fr12.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr12 AS ActivePath_fr12, UNNEST((ActivePath_fr12.logica_value).path) as x_1682
    WHERE
      ((ActivePath_fr12.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_1716 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr12 AS Opportunity_fr12, UNNEST(ARRAY[0]::numeric[]) as x_1716
      WHERE
        (Opportunity_fr12.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr12.logica_value = ROW((ActivePath_fr12.logica_value).path, (ActivePath_fr12.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f55.col0 AS col0,
  Flow_MultBodyAggAux_f55.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f55.logica_value) AS logica_value
FROM
  t_7_Flow_MultBodyAggAux_f55 AS Flow_MultBodyAggAux_f55
GROUP BY Flow_MultBodyAggAux_f55.col0, Flow_MultBodyAggAux_f55.col1;

-- Interacting with table logica_home.Flow_fr13

DROP TABLE IF EXISTS logica_home.ActivePath_fr13 CASCADE;
CREATE TABLE logica_home.ActivePath_fr13 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_328_Opportunity_fr12.path, t_328_Opportunity_fr12.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr12 AS t_328_Opportunity_fr12
    WHERE
      (t_328_Opportunity_fr12.logica_value > 0) AND
      (3 = t_328_Opportunity_fr12.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr13

DROP TABLE IF EXISTS logica_home.Capacity_fr12 CASCADE;
CREATE TABLE logica_home.Capacity_fr12 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_340_G.col0 AS col0,
      t_340_G.col1 AS col1,
      ((((t_340_G.logica_value) - (t_341_Flow_fr11.logica_value))) + (t_342_Flow_fr11.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_340_G, logica_home.Flow_fr11 AS t_341_Flow_fr11, logica_home.Flow_fr11 AS t_342_Flow_fr11
    WHERE
      (t_341_Flow_fr11.col0 = t_340_G.col0) AND
      (t_341_Flow_fr11.col1 = t_340_G.col1) AND
      (t_342_Flow_fr11.col0 = t_340_G.col1) AND
      (t_342_Flow_fr11.col1 = t_340_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr12

DROP TABLE IF EXISTS logica_home.Opportunity_fr13 CASCADE;
CREATE TABLE logica_home.Opportunity_fr13 AS WITH t_331_Opportunity_MultBodyAggAux_f56 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr12.col1 AS col0,
      ROW((t_336_Opportunity_fr12.path || ARRAY[ROW(t_336_Opportunity_fr12.col0, Capacity_fr12.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_336_Opportunity_fr12.logica_value, Capacity_fr12.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_336_Opportunity_fr12.logica_value, Capacity_fr12.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr12 AS t_336_Opportunity_fr12, logica_home.Capacity_fr12 AS Capacity_fr12
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_1901 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr12 AS t_343_ActivePath_fr12, UNNEST(ARRAY[0]::numeric[]) as x_1901) AS numeric) IS NULL) AND
      (Capacity_fr12.col0 = t_336_Opportunity_fr12.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f56.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f56.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f56.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f56.logica_value) AS logica_value
FROM
  t_331_Opportunity_MultBodyAggAux_f56 AS Opportunity_MultBodyAggAux_f56
GROUP BY Opportunity_MultBodyAggAux_f56.col0;

-- Interacting with table logica_home.Opportunity_fr13

DROP TABLE IF EXISTS logica_home.Flow_fr14 CASCADE;
CREATE TABLE logica_home.Flow_fr14 AS WITH t_6_Flow_MultBodyAggAux_f61 AS (SELECT * FROM (
  
    SELECT
      Flow_fr13.col0 AS col0,
      Flow_fr13.col1 AS col1,
      Flow_fr13.logica_value AS logica_value
    FROM
      logica_home.Flow_fr13 AS Flow_fr13 UNION ALL
  
    SELECT
      t_321_G.col0 AS col0,
      t_321_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_321_G UNION ALL
  
    SELECT
      (x_1797).x AS col0,
      (x_1797).y AS col1,
      (ActivePath_fr13.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr13 AS ActivePath_fr13, UNNEST((ActivePath_fr13.logica_value).path) as x_1797
    WHERE
      ((ActivePath_fr13.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_1831 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr13 AS Opportunity_fr13, UNNEST(ARRAY[0]::numeric[]) as x_1831
      WHERE
        (Opportunity_fr13.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr13.logica_value = ROW((ActivePath_fr13.logica_value).path, (ActivePath_fr13.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f61.col0 AS col0,
  Flow_MultBodyAggAux_f61.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f61.logica_value) AS logica_value
FROM
  t_6_Flow_MultBodyAggAux_f61 AS Flow_MultBodyAggAux_f61
GROUP BY Flow_MultBodyAggAux_f61.col0, Flow_MultBodyAggAux_f61.col1;

-- Interacting with table logica_home.Flow_fr14

DROP TABLE IF EXISTS logica_home.ActivePath_fr14 CASCADE;
CREATE TABLE logica_home.ActivePath_fr14 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_351_Opportunity_fr13.path, t_351_Opportunity_fr13.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr13 AS t_351_Opportunity_fr13
    WHERE
      (t_351_Opportunity_fr13.logica_value > 0) AND
      (3 = t_351_Opportunity_fr13.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr14

DROP TABLE IF EXISTS logica_home.Capacity_fr13 CASCADE;
CREATE TABLE logica_home.Capacity_fr13 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_363_G.col0 AS col0,
      t_363_G.col1 AS col1,
      ((((t_363_G.logica_value) - (t_364_Flow_fr12.logica_value))) + (t_365_Flow_fr12.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_363_G, logica_home.Flow_fr12 AS t_364_Flow_fr12, logica_home.Flow_fr12 AS t_365_Flow_fr12
    WHERE
      (t_364_Flow_fr12.col0 = t_363_G.col0) AND
      (t_364_Flow_fr12.col1 = t_363_G.col1) AND
      (t_365_Flow_fr12.col0 = t_363_G.col1) AND
      (t_365_Flow_fr12.col1 = t_363_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr13

DROP TABLE IF EXISTS logica_home.Opportunity_fr14 CASCADE;
CREATE TABLE logica_home.Opportunity_fr14 AS WITH t_354_Opportunity_MultBodyAggAux_f57 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr13.col1 AS col0,
      ROW((t_359_Opportunity_fr13.path || ARRAY[ROW(t_359_Opportunity_fr13.col0, Capacity_fr13.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_359_Opportunity_fr13.logica_value, Capacity_fr13.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_359_Opportunity_fr13.logica_value, Capacity_fr13.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr13 AS t_359_Opportunity_fr13, logica_home.Capacity_fr13 AS Capacity_fr13
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_2016 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr13 AS t_366_ActivePath_fr13, UNNEST(ARRAY[0]::numeric[]) as x_2016) AS numeric) IS NULL) AND
      (Capacity_fr13.col0 = t_359_Opportunity_fr13.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f57.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f57.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f57.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f57.logica_value) AS logica_value
FROM
  t_354_Opportunity_MultBodyAggAux_f57 AS Opportunity_MultBodyAggAux_f57
GROUP BY Opportunity_MultBodyAggAux_f57.col0;

-- Interacting with table logica_home.Opportunity_fr14

DROP TABLE IF EXISTS logica_home.Flow_fr15 CASCADE;
CREATE TABLE logica_home.Flow_fr15 AS WITH t_5_Flow_MultBodyAggAux_f62 AS (SELECT * FROM (
  
    SELECT
      Flow_fr14.col0 AS col0,
      Flow_fr14.col1 AS col1,
      Flow_fr14.logica_value AS logica_value
    FROM
      logica_home.Flow_fr14 AS Flow_fr14 UNION ALL
  
    SELECT
      t_344_G.col0 AS col0,
      t_344_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_344_G UNION ALL
  
    SELECT
      (x_1912).x AS col0,
      (x_1912).y AS col1,
      (ActivePath_fr14.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr14 AS ActivePath_fr14, UNNEST((ActivePath_fr14.logica_value).path) as x_1912
    WHERE
      ((ActivePath_fr14.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_1946 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr14 AS Opportunity_fr14, UNNEST(ARRAY[0]::numeric[]) as x_1946
      WHERE
        (Opportunity_fr14.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr14.logica_value = ROW((ActivePath_fr14.logica_value).path, (ActivePath_fr14.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f62.col0 AS col0,
  Flow_MultBodyAggAux_f62.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f62.logica_value) AS logica_value
FROM
  t_5_Flow_MultBodyAggAux_f62 AS Flow_MultBodyAggAux_f62
GROUP BY Flow_MultBodyAggAux_f62.col0, Flow_MultBodyAggAux_f62.col1;

-- Interacting with table logica_home.Flow_fr15

DROP TABLE IF EXISTS logica_home.ActivePath_fr15 CASCADE;
CREATE TABLE logica_home.ActivePath_fr15 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_374_Opportunity_fr14.path, t_374_Opportunity_fr14.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr14 AS t_374_Opportunity_fr14
    WHERE
      (t_374_Opportunity_fr14.logica_value > 0) AND
      (3 = t_374_Opportunity_fr14.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr15

DROP TABLE IF EXISTS logica_home.Capacity_fr14 CASCADE;
CREATE TABLE logica_home.Capacity_fr14 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_386_G.col0 AS col0,
      t_386_G.col1 AS col1,
      ((((t_386_G.logica_value) - (t_387_Flow_fr13.logica_value))) + (t_388_Flow_fr13.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_386_G, logica_home.Flow_fr13 AS t_387_Flow_fr13, logica_home.Flow_fr13 AS t_388_Flow_fr13
    WHERE
      (t_387_Flow_fr13.col0 = t_386_G.col0) AND
      (t_387_Flow_fr13.col1 = t_386_G.col1) AND
      (t_388_Flow_fr13.col0 = t_386_G.col1) AND
      (t_388_Flow_fr13.col1 = t_386_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr14

DROP TABLE IF EXISTS logica_home.Opportunity_fr15 CASCADE;
CREATE TABLE logica_home.Opportunity_fr15 AS WITH t_377_Opportunity_MultBodyAggAux_f63 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr14.col1 AS col0,
      ROW((t_382_Opportunity_fr14.path || ARRAY[ROW(t_382_Opportunity_fr14.col0, Capacity_fr14.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_382_Opportunity_fr14.logica_value, Capacity_fr14.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_382_Opportunity_fr14.logica_value, Capacity_fr14.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr14 AS t_382_Opportunity_fr14, logica_home.Capacity_fr14 AS Capacity_fr14
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_2131 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr14 AS t_389_ActivePath_fr14, UNNEST(ARRAY[0]::numeric[]) as x_2131) AS numeric) IS NULL) AND
      (Capacity_fr14.col0 = t_382_Opportunity_fr14.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f63.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f63.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f63.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f63.logica_value) AS logica_value
FROM
  t_377_Opportunity_MultBodyAggAux_f63 AS Opportunity_MultBodyAggAux_f63
GROUP BY Opportunity_MultBodyAggAux_f63.col0;

-- Interacting with table logica_home.Opportunity_fr15

DROP TABLE IF EXISTS logica_home.Flow_fr16 CASCADE;
CREATE TABLE logica_home.Flow_fr16 AS WITH t_4_Flow_MultBodyAggAux_f67 AS (SELECT * FROM (
  
    SELECT
      Flow_fr15.col0 AS col0,
      Flow_fr15.col1 AS col1,
      Flow_fr15.logica_value AS logica_value
    FROM
      logica_home.Flow_fr15 AS Flow_fr15 UNION ALL
  
    SELECT
      t_367_G.col0 AS col0,
      t_367_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_367_G UNION ALL
  
    SELECT
      (x_2027).x AS col0,
      (x_2027).y AS col1,
      (ActivePath_fr15.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr15 AS ActivePath_fr15, UNNEST((ActivePath_fr15.logica_value).path) as x_2027
    WHERE
      ((ActivePath_fr15.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_2061 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr15 AS Opportunity_fr15, UNNEST(ARRAY[0]::numeric[]) as x_2061
      WHERE
        (Opportunity_fr15.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr15.logica_value = ROW((ActivePath_fr15.logica_value).path, (ActivePath_fr15.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f67.col0 AS col0,
  Flow_MultBodyAggAux_f67.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f67.logica_value) AS logica_value
FROM
  t_4_Flow_MultBodyAggAux_f67 AS Flow_MultBodyAggAux_f67
GROUP BY Flow_MultBodyAggAux_f67.col0, Flow_MultBodyAggAux_f67.col1;

-- Interacting with table logica_home.Flow_fr16

DROP TABLE IF EXISTS logica_home.ActivePath_fr16 CASCADE;
CREATE TABLE logica_home.ActivePath_fr16 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_397_Opportunity_fr15.path, t_397_Opportunity_fr15.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr15 AS t_397_Opportunity_fr15
    WHERE
      (t_397_Opportunity_fr15.logica_value > 0) AND
      (3 = t_397_Opportunity_fr15.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr16

DROP TABLE IF EXISTS logica_home.Capacity_fr15 CASCADE;
CREATE TABLE logica_home.Capacity_fr15 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_409_G.col0 AS col0,
      t_409_G.col1 AS col1,
      ((((t_409_G.logica_value) - (t_410_Flow_fr14.logica_value))) + (t_411_Flow_fr14.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_409_G, logica_home.Flow_fr14 AS t_410_Flow_fr14, logica_home.Flow_fr14 AS t_411_Flow_fr14
    WHERE
      (t_410_Flow_fr14.col0 = t_409_G.col0) AND
      (t_410_Flow_fr14.col1 = t_409_G.col1) AND
      (t_411_Flow_fr14.col0 = t_409_G.col1) AND
      (t_411_Flow_fr14.col1 = t_409_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr15

DROP TABLE IF EXISTS logica_home.Opportunity_fr16 CASCADE;
CREATE TABLE logica_home.Opportunity_fr16 AS WITH t_400_Opportunity_MultBodyAggAux_f68 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr15.col1 AS col0,
      ROW((t_405_Opportunity_fr15.path || ARRAY[ROW(t_405_Opportunity_fr15.col0, Capacity_fr15.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_405_Opportunity_fr15.logica_value, Capacity_fr15.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_405_Opportunity_fr15.logica_value, Capacity_fr15.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr15 AS t_405_Opportunity_fr15, logica_home.Capacity_fr15 AS Capacity_fr15
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_2246 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr15 AS t_412_ActivePath_fr15, UNNEST(ARRAY[0]::numeric[]) as x_2246) AS numeric) IS NULL) AND
      (Capacity_fr15.col0 = t_405_Opportunity_fr15.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f68.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f68.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f68.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f68.logica_value) AS logica_value
FROM
  t_400_Opportunity_MultBodyAggAux_f68 AS Opportunity_MultBodyAggAux_f68
GROUP BY Opportunity_MultBodyAggAux_f68.col0;

-- Interacting with table logica_home.Opportunity_fr16

DROP TABLE IF EXISTS logica_home.Flow_fr17 CASCADE;
CREATE TABLE logica_home.Flow_fr17 AS WITH t_3_Flow_MultBodyAggAux_f73 AS (SELECT * FROM (
  
    SELECT
      Flow_fr16.col0 AS col0,
      Flow_fr16.col1 AS col1,
      Flow_fr16.logica_value AS logica_value
    FROM
      logica_home.Flow_fr16 AS Flow_fr16 UNION ALL
  
    SELECT
      t_390_G.col0 AS col0,
      t_390_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_390_G UNION ALL
  
    SELECT
      (x_2142).x AS col0,
      (x_2142).y AS col1,
      (ActivePath_fr16.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr16 AS ActivePath_fr16, UNNEST((ActivePath_fr16.logica_value).path) as x_2142
    WHERE
      ((ActivePath_fr16.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_2176 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr16 AS Opportunity_fr16, UNNEST(ARRAY[0]::numeric[]) as x_2176
      WHERE
        (Opportunity_fr16.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr16.logica_value = ROW((ActivePath_fr16.logica_value).path, (ActivePath_fr16.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f73.col0 AS col0,
  Flow_MultBodyAggAux_f73.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f73.logica_value) AS logica_value
FROM
  t_3_Flow_MultBodyAggAux_f73 AS Flow_MultBodyAggAux_f73
GROUP BY Flow_MultBodyAggAux_f73.col0, Flow_MultBodyAggAux_f73.col1;

-- Interacting with table logica_home.Flow_fr17

DROP TABLE IF EXISTS logica_home.ActivePath_fr17 CASCADE;
CREATE TABLE logica_home.ActivePath_fr17 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_420_Opportunity_fr16.path, t_420_Opportunity_fr16.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr16 AS t_420_Opportunity_fr16
    WHERE
      (t_420_Opportunity_fr16.logica_value > 0) AND
      (3 = t_420_Opportunity_fr16.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr17

DROP TABLE IF EXISTS logica_home.Capacity_fr16 CASCADE;
CREATE TABLE logica_home.Capacity_fr16 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_432_G.col0 AS col0,
      t_432_G.col1 AS col1,
      ((((t_432_G.logica_value) - (t_433_Flow_fr15.logica_value))) + (t_434_Flow_fr15.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_432_G, logica_home.Flow_fr15 AS t_433_Flow_fr15, logica_home.Flow_fr15 AS t_434_Flow_fr15
    WHERE
      (t_433_Flow_fr15.col0 = t_432_G.col0) AND
      (t_433_Flow_fr15.col1 = t_432_G.col1) AND
      (t_434_Flow_fr15.col0 = t_432_G.col1) AND
      (t_434_Flow_fr15.col1 = t_432_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr16

DROP TABLE IF EXISTS logica_home.Opportunity_fr17 CASCADE;
CREATE TABLE logica_home.Opportunity_fr17 AS WITH t_423_Opportunity_MultBodyAggAux_f69 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr16.col1 AS col0,
      ROW((t_428_Opportunity_fr16.path || ARRAY[ROW(t_428_Opportunity_fr16.col0, Capacity_fr16.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_428_Opportunity_fr16.logica_value, Capacity_fr16.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_428_Opportunity_fr16.logica_value, Capacity_fr16.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr16 AS t_428_Opportunity_fr16, logica_home.Capacity_fr16 AS Capacity_fr16
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_2361 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr16 AS t_435_ActivePath_fr16, UNNEST(ARRAY[0]::numeric[]) as x_2361) AS numeric) IS NULL) AND
      (Capacity_fr16.col0 = t_428_Opportunity_fr16.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f69.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f69.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f69.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f69.logica_value) AS logica_value
FROM
  t_423_Opportunity_MultBodyAggAux_f69 AS Opportunity_MultBodyAggAux_f69
GROUP BY Opportunity_MultBodyAggAux_f69.col0;

-- Interacting with table logica_home.Opportunity_fr17

DROP TABLE IF EXISTS logica_home.Flow_fr18 CASCADE;
CREATE TABLE logica_home.Flow_fr18 AS WITH t_2_Flow_MultBodyAggAux_f74 AS (SELECT * FROM (
  
    SELECT
      Flow_fr17.col0 AS col0,
      Flow_fr17.col1 AS col1,
      Flow_fr17.logica_value AS logica_value
    FROM
      logica_home.Flow_fr17 AS Flow_fr17 UNION ALL
  
    SELECT
      t_413_G.col0 AS col0,
      t_413_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_413_G UNION ALL
  
    SELECT
      (x_2257).x AS col0,
      (x_2257).y AS col1,
      (ActivePath_fr17.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr17 AS ActivePath_fr17, UNNEST((ActivePath_fr17.logica_value).path) as x_2257
    WHERE
      ((ActivePath_fr17.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_2291 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr17 AS Opportunity_fr17, UNNEST(ARRAY[0]::numeric[]) as x_2291
      WHERE
        (Opportunity_fr17.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr17.logica_value = ROW((ActivePath_fr17.logica_value).path, (ActivePath_fr17.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f74.col0 AS col0,
  Flow_MultBodyAggAux_f74.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f74.logica_value) AS logica_value
FROM
  t_2_Flow_MultBodyAggAux_f74 AS Flow_MultBodyAggAux_f74
GROUP BY Flow_MultBodyAggAux_f74.col0, Flow_MultBodyAggAux_f74.col1;

-- Interacting with table logica_home.Flow_fr18

DROP TABLE IF EXISTS logica_home.ActivePath_fr18 CASCADE;
CREATE TABLE logica_home.ActivePath_fr18 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_443_Opportunity_fr17.path, t_443_Opportunity_fr17.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr17 AS t_443_Opportunity_fr17
    WHERE
      (t_443_Opportunity_fr17.logica_value > 0) AND
      (3 = t_443_Opportunity_fr17.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr18

DROP TABLE IF EXISTS logica_home.Capacity_fr17 CASCADE;
CREATE TABLE logica_home.Capacity_fr17 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_455_G.col0 AS col0,
      t_455_G.col1 AS col1,
      ((((t_455_G.logica_value) - (t_456_Flow_fr16.logica_value))) + (t_457_Flow_fr16.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_455_G, logica_home.Flow_fr16 AS t_456_Flow_fr16, logica_home.Flow_fr16 AS t_457_Flow_fr16
    WHERE
      (t_456_Flow_fr16.col0 = t_455_G.col0) AND
      (t_456_Flow_fr16.col1 = t_455_G.col1) AND
      (t_457_Flow_fr16.col0 = t_455_G.col1) AND
      (t_457_Flow_fr16.col1 = t_455_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr17

DROP TABLE IF EXISTS logica_home.Opportunity_fr18 CASCADE;
CREATE TABLE logica_home.Opportunity_fr18 AS WITH t_446_Opportunity_MultBodyAggAux_f75 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr17.col1 AS col0,
      ROW((t_451_Opportunity_fr17.path || ARRAY[ROW(t_451_Opportunity_fr17.col0, Capacity_fr17.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_451_Opportunity_fr17.logica_value, Capacity_fr17.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_451_Opportunity_fr17.logica_value, Capacity_fr17.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr17 AS t_451_Opportunity_fr17, logica_home.Capacity_fr17 AS Capacity_fr17
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_2476 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr17 AS t_458_ActivePath_fr17, UNNEST(ARRAY[0]::numeric[]) as x_2476) AS numeric) IS NULL) AND
      (Capacity_fr17.col0 = t_451_Opportunity_fr17.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f75.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f75.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f75.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f75.logica_value) AS logica_value
FROM
  t_446_Opportunity_MultBodyAggAux_f75 AS Opportunity_MultBodyAggAux_f75
GROUP BY Opportunity_MultBodyAggAux_f75.col0;

-- Interacting with table logica_home.Opportunity_fr18

DROP TABLE IF EXISTS logica_home.Flow_fr19 CASCADE;
CREATE TABLE logica_home.Flow_fr19 AS WITH t_1_Flow_MultBodyAggAux_f79 AS (SELECT * FROM (
  
    SELECT
      Flow_fr18.col0 AS col0,
      Flow_fr18.col1 AS col1,
      Flow_fr18.logica_value AS logica_value
    FROM
      logica_home.Flow_fr18 AS Flow_fr18 UNION ALL
  
    SELECT
      t_436_G.col0 AS col0,
      t_436_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_436_G UNION ALL
  
    SELECT
      (x_2372).x AS col0,
      (x_2372).y AS col1,
      (ActivePath_fr18.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr18 AS ActivePath_fr18, UNNEST((ActivePath_fr18.logica_value).path) as x_2372
    WHERE
      ((ActivePath_fr18.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_2406 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr18 AS Opportunity_fr18, UNNEST(ARRAY[0]::numeric[]) as x_2406
      WHERE
        (Opportunity_fr18.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr18.logica_value = ROW((ActivePath_fr18.logica_value).path, (ActivePath_fr18.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f79.col0 AS col0,
  Flow_MultBodyAggAux_f79.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f79.logica_value) AS logica_value
FROM
  t_1_Flow_MultBodyAggAux_f79 AS Flow_MultBodyAggAux_f79
GROUP BY Flow_MultBodyAggAux_f79.col0, Flow_MultBodyAggAux_f79.col1;

-- Interacting with table logica_home.Flow_fr19

DROP TABLE IF EXISTS logica_home.ActivePath_fr19 CASCADE;
CREATE TABLE logica_home.ActivePath_fr19 AS SELECT * FROM (
  
    SELECT
      ROW(ARRAY[ROW(0, 0)::logicarecord6083990]::logicarecord6083990[], 0)::logicarecord865112836 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      ROW(t_466_Opportunity_fr18.path, t_466_Opportunity_fr18.logica_value)::logicarecord865112836 AS logica_value
    FROM
      logica_home.Opportunity_fr18 AS t_466_Opportunity_fr18
    WHERE
      (t_466_Opportunity_fr18.logica_value > 0) AND
      (3 = t_466_Opportunity_fr18.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.ActivePath_fr19

DROP TABLE IF EXISTS logica_home.Capacity_fr18 CASCADE;
CREATE TABLE logica_home.Capacity_fr18 AS SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS col1,
      0 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton
    WHERE
      (1 = 0) UNION ALL
  
    SELECT
      t_478_G.col0 AS col0,
      t_478_G.col1 AS col1,
      ((((t_478_G.logica_value) - (t_479_Flow_fr17.logica_value))) + (t_480_Flow_fr17.logica_value)) AS logica_value
    FROM
      logica_home.G AS t_478_G, logica_home.Flow_fr17 AS t_479_Flow_fr17, logica_home.Flow_fr17 AS t_480_Flow_fr17
    WHERE
      (t_479_Flow_fr17.col0 = t_478_G.col0) AND
      (t_479_Flow_fr17.col1 = t_478_G.col1) AND
      (t_480_Flow_fr17.col0 = t_478_G.col1) AND
      (t_480_Flow_fr17.col1 = t_478_G.col0)
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Capacity_fr18

DROP TABLE IF EXISTS logica_home.Opportunity_fr19 CASCADE;
CREATE TABLE logica_home.Opportunity_fr19 AS WITH t_469_Opportunity_MultBodyAggAux_f80 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      ROW(ARRAY[]::logicarecord6083990[], 100)::logicarecord870775962 AS path,
      100 AS logica_value
    FROM
      (SELECT 'singleton' as s) as unused_singleton UNION ALL
  
    SELECT
      Capacity_fr18.col1 AS col0,
      ROW((t_474_Opportunity_fr18.path || ARRAY[ROW(t_474_Opportunity_fr18.col0, Capacity_fr18.col1)::logicarecord6083990]::logicarecord6083990[]), ((LEAST(t_474_Opportunity_fr18.logica_value, Capacity_fr18.logica_value)) - (0.001)))::logicarecord870775962 AS path,
      ((LEAST(t_474_Opportunity_fr18.logica_value, Capacity_fr18.logica_value)) - (0.001)) AS logica_value
    FROM
      logica_home.Opportunity_fr18 AS t_474_Opportunity_fr18, logica_home.Capacity_fr18 AS Capacity_fr18
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_2591 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.ActivePath_fr18 AS t_481_ActivePath_fr18, UNNEST(ARRAY[0]::numeric[]) as x_2591) AS numeric) IS NULL) AND
      (Capacity_fr18.col0 = t_474_Opportunity_fr18.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  Opportunity_MultBodyAggAux_f80.col0 AS col0,
  ((ARRAY_AGG(ROW((Opportunity_MultBodyAggAux_f80.path).arg)::logicarecord565712478 order by (Opportunity_MultBodyAggAux_f80.path).value desc))[1]).argpod AS path,
  MAX(Opportunity_MultBodyAggAux_f80.logica_value) AS logica_value
FROM
  t_469_Opportunity_MultBodyAggAux_f80 AS Opportunity_MultBodyAggAux_f80
GROUP BY Opportunity_MultBodyAggAux_f80.col0;

-- Interacting with table logica_home.Opportunity_fr19

DROP TABLE IF EXISTS logica_home.Flow CASCADE;
CREATE TABLE logica_home.Flow AS WITH t_0_Flow_MultBodyAggAux_f84 AS (SELECT * FROM (
  
    SELECT
      Flow_fr19.col0 AS col0,
      Flow_fr19.col1 AS col1,
      Flow_fr19.logica_value AS logica_value
    FROM
      logica_home.Flow_fr19 AS Flow_fr19 UNION ALL
  
    SELECT
      t_459_G.col0 AS col0,
      t_459_G.col1 AS col1,
      0 AS logica_value
    FROM
      logica_home.G AS t_459_G UNION ALL
  
    SELECT
      (x_2487).x AS col0,
      (x_2487).y AS col1,
      (ActivePath_fr19.logica_value).v AS logica_value
    FROM
      logica_home.ActivePath_fr19 AS ActivePath_fr19, UNNEST((ActivePath_fr19.logica_value).path) as x_2487
    WHERE
      ((ActivePath_fr19.logica_value).v > 0) AND
      NOT (CAST((SELECT
        MIN((CASE WHEN x_2521 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        logica_home.Opportunity_fr19 AS Opportunity_fr19, UNNEST(ARRAY[0]::numeric[]) as x_2521
      WHERE
        (Opportunity_fr19.col0 = 3)) AS numeric) IS NULL) AND
      (ActivePath_fr19.logica_value = ROW((ActivePath_fr19.logica_value).path, (ActivePath_fr19.logica_value).v)::logicarecord865112836)
) AS UNUSED_TABLE_NAME  )
SELECT
  Flow_MultBodyAggAux_f84.col0 AS col0,
  Flow_MultBodyAggAux_f84.col1 AS col1,
  SUM(Flow_MultBodyAggAux_f84.logica_value) AS logica_value
FROM
  t_0_Flow_MultBodyAggAux_f84 AS Flow_MultBodyAggAux_f84
GROUP BY Flow_MultBodyAggAux_f84.col0, Flow_MultBodyAggAux_f84.col1;

-- Interacting with table logica_home.Flow

SELECT
  Flow.col0 AS col0,
  Flow.col1 AS col1,
  Flow.logica_value AS logica_value
FROM
  logica_home.Flow AS Flow ORDER BY col0, col1;
