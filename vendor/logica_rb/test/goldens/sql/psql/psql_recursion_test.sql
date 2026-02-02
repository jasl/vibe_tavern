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
-- Logica type: logicarecord605846997
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord605846997') then create type logicarecord605846997 as (d numeric, y numeric); end if;
-- Logica type: logicarecord428993633
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord428993633') then create type logicarecord428993633 as (arg numeric, value logicarecord605846997); end if;
END $$;


DROP TABLE IF EXISTS logica_home.Distance_ifr0 CASCADE;
CREATE TABLE logica_home.Distance_ifr0 AS WITH t_11_Edge AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      2 AS col1 UNION ALL
  
    SELECT
      2 AS col0,
      3 AS col1 UNION ALL
  
    SELECT
      3 AS col0,
      4 AS col1 UNION ALL
  
    SELECT
      4 AS col0,
      5 AS col1 UNION ALL
  
    SELECT
      6 AS col0,
      7 AS col1 UNION ALL
  
    SELECT
      7 AS col0,
      8 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      10 AS col1 UNION ALL
  
    SELECT
      10 AS col0,
      11 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      11 AS col1
) AS UNUSED_TABLE_NAME  ),
t_7_Distance_MultBodyAggAux_f1 AS (SELECT * FROM (
  
    SELECT
      Edge.col0 AS col0,
      Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_11_Edge AS Edge
) AS UNUSED_TABLE_NAME  )
SELECT
  Distance_MultBodyAggAux_f1.col0 AS col0,
  Distance_MultBodyAggAux_f1.col1 AS col1,
  MIN(Distance_MultBodyAggAux_f1.logica_value) AS logica_value
FROM
  t_7_Distance_MultBodyAggAux_f1 AS Distance_MultBodyAggAux_f1
GROUP BY Distance_MultBodyAggAux_f1.col0, Distance_MultBodyAggAux_f1.col1 ORDER BY col0, col1;

-- Interacting with table logica_home.Distance_ifr0

DROP TABLE IF EXISTS logica_home.Distance_ifr1 CASCADE;
CREATE TABLE logica_home.Distance_ifr1 AS WITH t_11_Edge AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      2 AS col1 UNION ALL
  
    SELECT
      2 AS col0,
      3 AS col1 UNION ALL
  
    SELECT
      3 AS col0,
      4 AS col1 UNION ALL
  
    SELECT
      4 AS col0,
      5 AS col1 UNION ALL
  
    SELECT
      6 AS col0,
      7 AS col1 UNION ALL
  
    SELECT
      7 AS col0,
      8 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      10 AS col1 UNION ALL
  
    SELECT
      10 AS col0,
      11 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      11 AS col1
) AS UNUSED_TABLE_NAME  ),
t_6_Distance_MultBodyAggAux_f2 AS (SELECT * FROM (
  
    SELECT
      Distance_ifr0.col0 AS col0,
      Distance_ifr0.col0 AS col1,
      0 AS logica_value
    FROM
      logica_home.Distance_ifr0 AS Distance_ifr0 UNION ALL
  
    SELECT
      t_12_Distance_ifr0.col0 AS col0,
      t_13_Distance_ifr0.col1 AS col1,
      ((t_12_Distance_ifr0.logica_value) + (t_13_Distance_ifr0.logica_value)) AS logica_value
    FROM
      logica_home.Distance_ifr0 AS t_12_Distance_ifr0, logica_home.Distance_ifr0 AS t_13_Distance_ifr0
    WHERE
      (t_13_Distance_ifr0.col0 = t_12_Distance_ifr0.col1) UNION ALL
  
    SELECT
      t_14_Distance_ifr0.col1 AS col0,
      t_14_Distance_ifr0.col0 AS col1,
      t_14_Distance_ifr0.logica_value AS logica_value
    FROM
      logica_home.Distance_ifr0 AS t_14_Distance_ifr0 UNION ALL
  
    SELECT
      t_15_Edge.col0 AS col0,
      t_15_Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_11_Edge AS t_15_Edge
) AS UNUSED_TABLE_NAME  )
SELECT
  Distance_MultBodyAggAux_f2.col0 AS col0,
  Distance_MultBodyAggAux_f2.col1 AS col1,
  MIN(Distance_MultBodyAggAux_f2.logica_value) AS logica_value
FROM
  t_6_Distance_MultBodyAggAux_f2 AS Distance_MultBodyAggAux_f2
GROUP BY Distance_MultBodyAggAux_f2.col0, Distance_MultBodyAggAux_f2.col1 ORDER BY col0, col1;

-- Interacting with table logica_home.Distance_ifr1

DROP TABLE IF EXISTS logica_home.Distance_ifr2 CASCADE;
CREATE TABLE logica_home.Distance_ifr2 AS WITH t_11_Edge AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      2 AS col1 UNION ALL
  
    SELECT
      2 AS col0,
      3 AS col1 UNION ALL
  
    SELECT
      3 AS col0,
      4 AS col1 UNION ALL
  
    SELECT
      4 AS col0,
      5 AS col1 UNION ALL
  
    SELECT
      6 AS col0,
      7 AS col1 UNION ALL
  
    SELECT
      7 AS col0,
      8 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      10 AS col1 UNION ALL
  
    SELECT
      10 AS col0,
      11 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      11 AS col1
) AS UNUSED_TABLE_NAME  ),
t_5_Distance_MultBodyAggAux_f3 AS (SELECT * FROM (
  
    SELECT
      Distance_ifr1.col0 AS col0,
      Distance_ifr1.col0 AS col1,
      0 AS logica_value
    FROM
      logica_home.Distance_ifr1 AS Distance_ifr1 UNION ALL
  
    SELECT
      t_16_Distance_ifr1.col0 AS col0,
      t_17_Distance_ifr1.col1 AS col1,
      ((t_16_Distance_ifr1.logica_value) + (t_17_Distance_ifr1.logica_value)) AS logica_value
    FROM
      logica_home.Distance_ifr1 AS t_16_Distance_ifr1, logica_home.Distance_ifr1 AS t_17_Distance_ifr1
    WHERE
      (t_17_Distance_ifr1.col0 = t_16_Distance_ifr1.col1) UNION ALL
  
    SELECT
      t_18_Distance_ifr1.col1 AS col0,
      t_18_Distance_ifr1.col0 AS col1,
      t_18_Distance_ifr1.logica_value AS logica_value
    FROM
      logica_home.Distance_ifr1 AS t_18_Distance_ifr1 UNION ALL
  
    SELECT
      t_19_Edge.col0 AS col0,
      t_19_Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_11_Edge AS t_19_Edge
) AS UNUSED_TABLE_NAME  )
SELECT
  Distance_MultBodyAggAux_f3.col0 AS col0,
  Distance_MultBodyAggAux_f3.col1 AS col1,
  MIN(Distance_MultBodyAggAux_f3.logica_value) AS logica_value
FROM
  t_5_Distance_MultBodyAggAux_f3 AS Distance_MultBodyAggAux_f3
GROUP BY Distance_MultBodyAggAux_f3.col0, Distance_MultBodyAggAux_f3.col1 ORDER BY col0, col1;

-- Interacting with table logica_home.Distance_ifr2

DROP TABLE IF EXISTS logica_home.Distance_ifr1 CASCADE;
CREATE TABLE logica_home.Distance_ifr1 AS WITH t_11_Edge AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      2 AS col1 UNION ALL
  
    SELECT
      2 AS col0,
      3 AS col1 UNION ALL
  
    SELECT
      3 AS col0,
      4 AS col1 UNION ALL
  
    SELECT
      4 AS col0,
      5 AS col1 UNION ALL
  
    SELECT
      6 AS col0,
      7 AS col1 UNION ALL
  
    SELECT
      7 AS col0,
      8 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      10 AS col1 UNION ALL
  
    SELECT
      10 AS col0,
      11 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      11 AS col1
) AS UNUSED_TABLE_NAME  ),
t_4_Distance_MultBodyAggAux_f4 AS (SELECT * FROM (
  
    SELECT
      Distance_ifr2.col0 AS col0,
      Distance_ifr2.col0 AS col1,
      0 AS logica_value
    FROM
      logica_home.Distance_ifr2 AS Distance_ifr2 UNION ALL
  
    SELECT
      t_20_Distance_ifr2.col0 AS col0,
      t_21_Distance_ifr2.col1 AS col1,
      ((t_20_Distance_ifr2.logica_value) + (t_21_Distance_ifr2.logica_value)) AS logica_value
    FROM
      logica_home.Distance_ifr2 AS t_20_Distance_ifr2, logica_home.Distance_ifr2 AS t_21_Distance_ifr2
    WHERE
      (t_21_Distance_ifr2.col0 = t_20_Distance_ifr2.col1) UNION ALL
  
    SELECT
      t_22_Distance_ifr2.col1 AS col0,
      t_22_Distance_ifr2.col0 AS col1,
      t_22_Distance_ifr2.logica_value AS logica_value
    FROM
      logica_home.Distance_ifr2 AS t_22_Distance_ifr2 UNION ALL
  
    SELECT
      t_23_Edge.col0 AS col0,
      t_23_Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_11_Edge AS t_23_Edge
) AS UNUSED_TABLE_NAME  )
SELECT
  Distance_MultBodyAggAux_f4.col0 AS col0,
  Distance_MultBodyAggAux_f4.col1 AS col1,
  MIN(Distance_MultBodyAggAux_f4.logica_value) AS logica_value
FROM
  t_4_Distance_MultBodyAggAux_f4 AS Distance_MultBodyAggAux_f4
GROUP BY Distance_MultBodyAggAux_f4.col0, Distance_MultBodyAggAux_f4.col1 ORDER BY col0, col1;

-- Interacting with table logica_home.Distance_ifr1

DROP TABLE IF EXISTS logica_home.Distance CASCADE;
CREATE TABLE logica_home.Distance AS WITH t_11_Edge AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      2 AS col1 UNION ALL
  
    SELECT
      2 AS col0,
      3 AS col1 UNION ALL
  
    SELECT
      3 AS col0,
      4 AS col1 UNION ALL
  
    SELECT
      4 AS col0,
      5 AS col1 UNION ALL
  
    SELECT
      6 AS col0,
      7 AS col1 UNION ALL
  
    SELECT
      7 AS col0,
      8 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      10 AS col1 UNION ALL
  
    SELECT
      10 AS col0,
      11 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      11 AS col1
) AS UNUSED_TABLE_NAME  ),
t_3_Distance_MultBodyAggAux_f5 AS (SELECT * FROM (
  
    SELECT
      Distance_ifr3.col0 AS col0,
      Distance_ifr3.col0 AS col1,
      0 AS logica_value
    FROM
      logica_home.Distance_ifr1 AS Distance_ifr3 UNION ALL
  
    SELECT
      t_24_Distance_ifr3.col0 AS col0,
      t_25_Distance_ifr3.col1 AS col1,
      ((t_24_Distance_ifr3.logica_value) + (t_25_Distance_ifr3.logica_value)) AS logica_value
    FROM
      logica_home.Distance_ifr1 AS t_24_Distance_ifr3, logica_home.Distance_ifr1 AS t_25_Distance_ifr3
    WHERE
      (t_25_Distance_ifr3.col0 = t_24_Distance_ifr3.col1) UNION ALL
  
    SELECT
      t_26_Distance_ifr3.col1 AS col0,
      t_26_Distance_ifr3.col0 AS col1,
      t_26_Distance_ifr3.logica_value AS logica_value
    FROM
      logica_home.Distance_ifr1 AS t_26_Distance_ifr3 UNION ALL
  
    SELECT
      t_27_Edge.col0 AS col0,
      t_27_Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_11_Edge AS t_27_Edge
) AS UNUSED_TABLE_NAME  )
SELECT
  Distance_MultBodyAggAux_f5.col0 AS col0,
  Distance_MultBodyAggAux_f5.col1 AS col1,
  MIN(Distance_MultBodyAggAux_f5.logica_value) AS logica_value
FROM
  t_3_Distance_MultBodyAggAux_f5 AS Distance_MultBodyAggAux_f5
GROUP BY Distance_MultBodyAggAux_f5.col0, Distance_MultBodyAggAux_f5.col1 ORDER BY col0, col1;

-- Interacting with table logica_home.Distance

WITH t_1_ComponentOf AS (SELECT
  t_2_Distance.col0 AS col0,
  MIN(t_2_Distance.col1) AS logica_value
FROM
  logica_home.Distance AS t_2_Distance
GROUP BY t_2_Distance.col0 ORDER BY col0)
SELECT
  ComponentOf.col0 AS vertex,
  ComponentOf.logica_value AS component,
  ARRAY_AGG(ROW(Distance.logica_value, Distance.col1)::logicarecord605846997 order by - Distance.col1) AS distances
FROM
  t_1_ComponentOf AS ComponentOf, logica_home.Distance AS Distance
WHERE
  (Distance.col0 = ComponentOf.col0)
GROUP BY ComponentOf.col0, ComponentOf.logica_value ORDER BY vertex;
