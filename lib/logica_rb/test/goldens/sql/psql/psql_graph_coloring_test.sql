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
END $$;


DROP TABLE IF EXISTS logica_home.L_ifr0 CASCADE;
CREATE TABLE logica_home.L_ifr0 AS WITH t_16_L_MultBodyAggAux_f1 AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      1 AS col1,
      2 AS col2,
      1 AS col3
) AS UNUSED_TABLE_NAME  )
SELECT
  L_MultBodyAggAux_f1.col0 AS col0,
  L_MultBodyAggAux_f1.col1 AS col1,
  L_MultBodyAggAux_f1.col2 AS col2,
  L_MultBodyAggAux_f1.col3 AS col3
FROM
  t_16_L_MultBodyAggAux_f1 AS L_MultBodyAggAux_f1
GROUP BY L_MultBodyAggAux_f1.col0, L_MultBodyAggAux_f1.col1, L_MultBodyAggAux_f1.col2, L_MultBodyAggAux_f1.col3;

-- Interacting with table logica_home.L_ifr0

DROP TABLE IF EXISTS logica_home.L_ifr1 CASCADE;
CREATE TABLE logica_home.L_ifr1 AS WITH t_15_L_MultBodyAggAux_f2 AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      1 AS col1,
      2 AS col2,
      1 AS col3 UNION ALL
  
    SELECT
      L_ifr0.col2 AS col0,
      L_ifr0.col3 AS col1,
      ((L_ifr0.col2) * (2)) AS col2,
      L_ifr0.col3 AS col3
    FROM
      logica_home.L_ifr0 AS L_ifr0 UNION ALL
  
    SELECT
      t_18_L_ifr0.col2 AS col0,
      t_18_L_ifr0.col3 AS col1,
      t_18_L_ifr0.col2 AS col2,
      ((t_18_L_ifr0.col3) * (3)) AS col3
    FROM
      logica_home.L_ifr0 AS t_18_L_ifr0
) AS UNUSED_TABLE_NAME  )
SELECT
  L_MultBodyAggAux_f2.col0 AS col0,
  L_MultBodyAggAux_f2.col1 AS col1,
  L_MultBodyAggAux_f2.col2 AS col2,
  L_MultBodyAggAux_f2.col3 AS col3
FROM
  t_15_L_MultBodyAggAux_f2 AS L_MultBodyAggAux_f2
GROUP BY L_MultBodyAggAux_f2.col0, L_MultBodyAggAux_f2.col1, L_MultBodyAggAux_f2.col2, L_MultBodyAggAux_f2.col3;

-- Interacting with table logica_home.L_ifr1

DROP TABLE IF EXISTS logica_home.L_ifr2 CASCADE;
CREATE TABLE logica_home.L_ifr2 AS WITH t_14_L_MultBodyAggAux_f3 AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      1 AS col1,
      2 AS col2,
      1 AS col3 UNION ALL
  
    SELECT
      L_ifr1.col2 AS col0,
      L_ifr1.col3 AS col1,
      ((L_ifr1.col2) * (2)) AS col2,
      L_ifr1.col3 AS col3
    FROM
      logica_home.L_ifr1 AS L_ifr1 UNION ALL
  
    SELECT
      t_19_L_ifr1.col2 AS col0,
      t_19_L_ifr1.col3 AS col1,
      t_19_L_ifr1.col2 AS col2,
      ((t_19_L_ifr1.col3) * (3)) AS col3
    FROM
      logica_home.L_ifr1 AS t_19_L_ifr1
) AS UNUSED_TABLE_NAME  )
SELECT
  L_MultBodyAggAux_f3.col0 AS col0,
  L_MultBodyAggAux_f3.col1 AS col1,
  L_MultBodyAggAux_f3.col2 AS col2,
  L_MultBodyAggAux_f3.col3 AS col3
FROM
  t_14_L_MultBodyAggAux_f3 AS L_MultBodyAggAux_f3
GROUP BY L_MultBodyAggAux_f3.col0, L_MultBodyAggAux_f3.col1, L_MultBodyAggAux_f3.col2, L_MultBodyAggAux_f3.col3;

-- Interacting with table logica_home.L_ifr2

DROP TABLE IF EXISTS logica_home.L_ifr1 CASCADE;
CREATE TABLE logica_home.L_ifr1 AS WITH t_13_L_MultBodyAggAux_f4 AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      1 AS col1,
      2 AS col2,
      1 AS col3 UNION ALL
  
    SELECT
      L_ifr2.col2 AS col0,
      L_ifr2.col3 AS col1,
      ((L_ifr2.col2) * (2)) AS col2,
      L_ifr2.col3 AS col3
    FROM
      logica_home.L_ifr2 AS L_ifr2 UNION ALL
  
    SELECT
      t_20_L_ifr2.col2 AS col0,
      t_20_L_ifr2.col3 AS col1,
      t_20_L_ifr2.col2 AS col2,
      ((t_20_L_ifr2.col3) * (3)) AS col3
    FROM
      logica_home.L_ifr2 AS t_20_L_ifr2
) AS UNUSED_TABLE_NAME  )
SELECT
  L_MultBodyAggAux_f4.col0 AS col0,
  L_MultBodyAggAux_f4.col1 AS col1,
  L_MultBodyAggAux_f4.col2 AS col2,
  L_MultBodyAggAux_f4.col3 AS col3
FROM
  t_13_L_MultBodyAggAux_f4 AS L_MultBodyAggAux_f4
GROUP BY L_MultBodyAggAux_f4.col0, L_MultBodyAggAux_f4.col1, L_MultBodyAggAux_f4.col2, L_MultBodyAggAux_f4.col3;

-- Interacting with table logica_home.L_ifr1

DROP TABLE IF EXISTS logica_home.L CASCADE;
CREATE TABLE logica_home.L AS WITH t_12_L_MultBodyAggAux_f5 AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      1 AS col1,
      2 AS col2,
      1 AS col3 UNION ALL
  
    SELECT
      L_ifr3.col2 AS col0,
      L_ifr3.col3 AS col1,
      ((L_ifr3.col2) * (2)) AS col2,
      L_ifr3.col3 AS col3
    FROM
      logica_home.L_ifr1 AS L_ifr3 UNION ALL
  
    SELECT
      t_21_L_ifr3.col2 AS col0,
      t_21_L_ifr3.col3 AS col1,
      t_21_L_ifr3.col2 AS col2,
      ((t_21_L_ifr3.col3) * (3)) AS col3
    FROM
      logica_home.L_ifr1 AS t_21_L_ifr3
) AS UNUSED_TABLE_NAME  )
SELECT
  L_MultBodyAggAux_f5.col0 AS col0,
  L_MultBodyAggAux_f5.col1 AS col1,
  L_MultBodyAggAux_f5.col2 AS col2,
  L_MultBodyAggAux_f5.col3 AS col3
FROM
  t_12_L_MultBodyAggAux_f5 AS L_MultBodyAggAux_f5
GROUP BY L_MultBodyAggAux_f5.col0, L_MultBodyAggAux_f5.col1, L_MultBodyAggAux_f5.col2, L_MultBodyAggAux_f5.col3;

-- Interacting with table logica_home.L

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr0 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr0 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_74_ComponentOf_MultBodyAggAux_f7 AS (SELECT * FROM (
  
    SELECT
      t_77_E.col0 AS col0,
      t_77_E.col0 AS logica_value
    FROM
      t_4_E AS t_77_E
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f7.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f7.logica_value) AS logica_value
FROM
  t_74_ComponentOf_MultBodyAggAux_f7 AS ComponentOf_MultBodyAggAux_f7
GROUP BY ComponentOf_MultBodyAggAux_f7.col0;

-- Interacting with table logica_home.ComponentOf_ifr0

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr1 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr1 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_63_ComponentOf_MultBodyAggAux_f8 AS (SELECT * FROM (
  
    SELECT
      t_64_E.col0 AS col0,
      ComponentOf_ifr0.logica_value AS logica_value
    FROM
      t_4_E AS t_64_E, logica_home.ComponentOf_ifr0 AS ComponentOf_ifr0
    WHERE
      (ComponentOf_ifr0.col0 = t_64_E.col1) UNION ALL
  
    SELECT
      t_87_E.col0 AS col0,
      t_87_E.col0 AS logica_value
    FROM
      t_4_E AS t_87_E
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f8.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f8.logica_value) AS logica_value
FROM
  t_63_ComponentOf_MultBodyAggAux_f8 AS ComponentOf_MultBodyAggAux_f8
GROUP BY ComponentOf_MultBodyAggAux_f8.col0;

-- Interacting with table logica_home.ComponentOf_ifr1

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr2 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr2 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_52_ComponentOf_MultBodyAggAux_f9 AS (SELECT * FROM (
  
    SELECT
      t_53_E.col0 AS col0,
      ComponentOf_ifr1.logica_value AS logica_value
    FROM
      t_4_E AS t_53_E, logica_home.ComponentOf_ifr1 AS ComponentOf_ifr1
    WHERE
      (ComponentOf_ifr1.col0 = t_53_E.col1) UNION ALL
  
    SELECT
      t_88_E.col0 AS col0,
      t_88_E.col0 AS logica_value
    FROM
      t_4_E AS t_88_E
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f9.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f9.logica_value) AS logica_value
FROM
  t_52_ComponentOf_MultBodyAggAux_f9 AS ComponentOf_MultBodyAggAux_f9
GROUP BY ComponentOf_MultBodyAggAux_f9.col0;

-- Interacting with table logica_home.ComponentOf_ifr2

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr3 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr3 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_41_ComponentOf_MultBodyAggAux_f10 AS (SELECT * FROM (
  
    SELECT
      t_42_E.col0 AS col0,
      ComponentOf_ifr2.logica_value AS logica_value
    FROM
      t_4_E AS t_42_E, logica_home.ComponentOf_ifr2 AS ComponentOf_ifr2
    WHERE
      (ComponentOf_ifr2.col0 = t_42_E.col1) UNION ALL
  
    SELECT
      t_89_E.col0 AS col0,
      t_89_E.col0 AS logica_value
    FROM
      t_4_E AS t_89_E
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f10.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f10.logica_value) AS logica_value
FROM
  t_41_ComponentOf_MultBodyAggAux_f10 AS ComponentOf_MultBodyAggAux_f10
GROUP BY ComponentOf_MultBodyAggAux_f10.col0;

-- Interacting with table logica_home.ComponentOf_ifr3

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr2 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr2 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_30_ComponentOf_MultBodyAggAux_f11 AS (SELECT * FROM (
  
    SELECT
      t_31_E.col0 AS col0,
      ComponentOf_ifr3.logica_value AS logica_value
    FROM
      t_4_E AS t_31_E, logica_home.ComponentOf_ifr3 AS ComponentOf_ifr3
    WHERE
      (ComponentOf_ifr3.col0 = t_31_E.col1) UNION ALL
  
    SELECT
      t_90_E.col0 AS col0,
      t_90_E.col0 AS logica_value
    FROM
      t_4_E AS t_90_E
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f11.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f11.logica_value) AS logica_value
FROM
  t_30_ComponentOf_MultBodyAggAux_f11 AS ComponentOf_MultBodyAggAux_f11
GROUP BY ComponentOf_MultBodyAggAux_f11.col0;

-- Interacting with table logica_home.ComponentOf_ifr2

DROP TABLE IF EXISTS logica_home.ComponentOf CASCADE;
CREATE TABLE logica_home.ComponentOf AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_2_ComponentOf_MultBodyAggAux_f12 AS (SELECT * FROM (
  
    SELECT
      t_3_E.col0 AS col0,
      ComponentOf_ifr4.logica_value AS logica_value
    FROM
      t_4_E AS t_3_E, logica_home.ComponentOf_ifr2 AS ComponentOf_ifr4
    WHERE
      (ComponentOf_ifr4.col0 = t_3_E.col1) UNION ALL
  
    SELECT
      t_91_E.col0 AS col0,
      t_91_E.col0 AS logica_value
    FROM
      t_4_E AS t_91_E
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f12.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f12.logica_value) AS logica_value
FROM
  t_2_ComponentOf_MultBodyAggAux_f12 AS ComponentOf_MultBodyAggAux_f12
GROUP BY ComponentOf_MultBodyAggAux_f12.col0;

-- Interacting with table logica_home.ComponentOf

DROP TABLE IF EXISTS logica_home.Color_ifr0 CASCADE;
CREATE TABLE logica_home.Color_ifr0 AS WITH t_1_ComponentStart AS (SELECT
  ComponentOf.logica_value AS logica_value
FROM
  logica_home.ComponentOf AS ComponentOf
GROUP BY ComponentOf.logica_value),
t_149_Color_MultBodyAggAux_f14 AS (SELECT * FROM (
  
    SELECT
      t_150_ComponentStart.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_1_ComponentStart AS t_150_ComponentStart
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f14.col0 AS col0,
  Color_MultBodyAggAux_f14.logica_value AS logica_value
FROM
  t_149_Color_MultBodyAggAux_f14 AS Color_MultBodyAggAux_f14
GROUP BY Color_MultBodyAggAux_f14.col0, Color_MultBodyAggAux_f14.logica_value;

-- Interacting with table logica_home.Color_ifr0

DROP TABLE IF EXISTS logica_home.Color_ifr1 CASCADE;
CREATE TABLE logica_home.Color_ifr1 AS WITH t_1_ComponentStart AS (SELECT
  ComponentOf.logica_value AS logica_value
FROM
  logica_home.ComponentOf AS ComponentOf
GROUP BY ComponentOf.logica_value),
t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_156_Other AS (SELECT * FROM (
  
    SELECT
      '#eee' AS col0,
      '#bbb' AS logica_value UNION ALL
  
    SELECT
      '#bbb' AS col0,
      '#eee' AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_134_Color_MultBodyAggAux_f15 AS (SELECT * FROM (
  
    SELECT
      t_135_ComponentStart.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_1_ComponentStart AS t_135_ComponentStart UNION ALL
  
    SELECT
      t_138_E.col1 AS col0,
      t_139_Other.logica_value AS logica_value
    FROM
      t_4_E AS t_138_E, logica_home.Color_ifr0 AS Color_ifr0, t_156_Other AS t_139_Other
    WHERE
      (Color_ifr0.col0 = t_138_E.col0) AND
      (t_139_Other.col0 = Color_ifr0.logica_value)
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f15.col0 AS col0,
  Color_MultBodyAggAux_f15.logica_value AS logica_value
FROM
  t_134_Color_MultBodyAggAux_f15 AS Color_MultBodyAggAux_f15
GROUP BY Color_MultBodyAggAux_f15.col0, Color_MultBodyAggAux_f15.logica_value;

-- Interacting with table logica_home.Color_ifr1

DROP TABLE IF EXISTS logica_home.Color_ifr2 CASCADE;
CREATE TABLE logica_home.Color_ifr2 AS WITH t_1_ComponentStart AS (SELECT
  ComponentOf.logica_value AS logica_value
FROM
  logica_home.ComponentOf AS ComponentOf
GROUP BY ComponentOf.logica_value),
t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_156_Other AS (SELECT * FROM (
  
    SELECT
      '#eee' AS col0,
      '#bbb' AS logica_value UNION ALL
  
    SELECT
      '#bbb' AS col0,
      '#eee' AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_119_Color_MultBodyAggAux_f16 AS (SELECT * FROM (
  
    SELECT
      t_120_ComponentStart.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_1_ComponentStart AS t_120_ComponentStart UNION ALL
  
    SELECT
      t_123_E.col1 AS col0,
      t_124_Other.logica_value AS logica_value
    FROM
      t_4_E AS t_123_E, logica_home.Color_ifr1 AS Color_ifr1, t_156_Other AS t_124_Other
    WHERE
      (Color_ifr1.col0 = t_123_E.col0) AND
      (t_124_Other.col0 = Color_ifr1.logica_value)
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f16.col0 AS col0,
  Color_MultBodyAggAux_f16.logica_value AS logica_value
FROM
  t_119_Color_MultBodyAggAux_f16 AS Color_MultBodyAggAux_f16
GROUP BY Color_MultBodyAggAux_f16.col0, Color_MultBodyAggAux_f16.logica_value;

-- Interacting with table logica_home.Color_ifr2

DROP TABLE IF EXISTS logica_home.Color_ifr1 CASCADE;
CREATE TABLE logica_home.Color_ifr1 AS WITH t_1_ComponentStart AS (SELECT
  ComponentOf.logica_value AS logica_value
FROM
  logica_home.ComponentOf AS ComponentOf
GROUP BY ComponentOf.logica_value),
t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_156_Other AS (SELECT * FROM (
  
    SELECT
      '#eee' AS col0,
      '#bbb' AS logica_value UNION ALL
  
    SELECT
      '#bbb' AS col0,
      '#eee' AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_104_Color_MultBodyAggAux_f17 AS (SELECT * FROM (
  
    SELECT
      t_105_ComponentStart.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_1_ComponentStart AS t_105_ComponentStart UNION ALL
  
    SELECT
      t_108_E.col1 AS col0,
      t_109_Other.logica_value AS logica_value
    FROM
      t_4_E AS t_108_E, logica_home.Color_ifr2 AS Color_ifr2, t_156_Other AS t_109_Other
    WHERE
      (Color_ifr2.col0 = t_108_E.col0) AND
      (t_109_Other.col0 = Color_ifr2.logica_value)
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f17.col0 AS col0,
  Color_MultBodyAggAux_f17.logica_value AS logica_value
FROM
  t_104_Color_MultBodyAggAux_f17 AS Color_MultBodyAggAux_f17
GROUP BY Color_MultBodyAggAux_f17.col0, Color_MultBodyAggAux_f17.logica_value;

-- Interacting with table logica_home.Color_ifr1

DROP TABLE IF EXISTS logica_home.Color CASCADE;
CREATE TABLE logica_home.Color AS WITH t_1_ComponentStart AS (SELECT
  ComponentOf.logica_value AS logica_value
FROM
  logica_home.ComponentOf AS ComponentOf
GROUP BY ComponentOf.logica_value),
t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_156_Other AS (SELECT * FROM (
  
    SELECT
      '#eee' AS col0,
      '#bbb' AS logica_value UNION ALL
  
    SELECT
      '#bbb' AS col0,
      '#eee' AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_0_Color_MultBodyAggAux_f18 AS (SELECT * FROM (
  
    SELECT
      ComponentStart.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_1_ComponentStart AS ComponentStart UNION ALL
  
    SELECT
      t_94_E.col1 AS col0,
      Other.logica_value AS logica_value
    FROM
      t_4_E AS t_94_E, logica_home.Color_ifr1 AS Color_ifr3, t_156_Other AS Other
    WHERE
      (Color_ifr3.col0 = t_94_E.col0) AND
      (Other.col0 = Color_ifr3.logica_value)
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f18.col0 AS col0,
  Color_MultBodyAggAux_f18.logica_value AS logica_value
FROM
  t_0_Color_MultBodyAggAux_f18 AS Color_MultBodyAggAux_f18
GROUP BY Color_MultBodyAggAux_f18.col0, Color_MultBodyAggAux_f18.logica_value;

-- Interacting with table logica_home.Color

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr0_f20 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr0_f20 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_258_ComponentOf_MultBodyAggAux_f7_f20 AS (SELECT * FROM (
  
    SELECT
      t_261_E_f20.col0 AS col0,
      t_261_E_f20.col0 AS logica_value
    FROM
      t_186_E_f20 AS t_261_E_f20
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f7_f20.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f7_f20.logica_value) AS logica_value
FROM
  t_258_ComponentOf_MultBodyAggAux_f7_f20 AS ComponentOf_MultBodyAggAux_f7_f20
GROUP BY ComponentOf_MultBodyAggAux_f7_f20.col0;

-- Interacting with table logica_home.ComponentOf_ifr0_f20

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr1_f20 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr1_f20 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_244_ComponentOf_MultBodyAggAux_f8_f20 AS (SELECT * FROM (
  
    SELECT
      t_245_E_f20.col0 AS col0,
      ComponentOf_ifr0_f20.logica_value AS logica_value
    FROM
      t_186_E_f20 AS t_245_E_f20, logica_home.ComponentOf_ifr0_f20 AS ComponentOf_ifr0_f20
    WHERE
      (ComponentOf_ifr0_f20.col0 = t_245_E_f20.col1) UNION ALL
  
    SELECT
      t_274_E_f20.col0 AS col0,
      t_274_E_f20.col0 AS logica_value
    FROM
      t_186_E_f20 AS t_274_E_f20
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f8_f20.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f8_f20.logica_value) AS logica_value
FROM
  t_244_ComponentOf_MultBodyAggAux_f8_f20 AS ComponentOf_MultBodyAggAux_f8_f20
GROUP BY ComponentOf_MultBodyAggAux_f8_f20.col0;

-- Interacting with table logica_home.ComponentOf_ifr1_f20

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr2_f20 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr2_f20 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_230_ComponentOf_MultBodyAggAux_f9_f20 AS (SELECT * FROM (
  
    SELECT
      t_231_E_f20.col0 AS col0,
      ComponentOf_ifr1_f20.logica_value AS logica_value
    FROM
      t_186_E_f20 AS t_231_E_f20, logica_home.ComponentOf_ifr1_f20 AS ComponentOf_ifr1_f20
    WHERE
      (ComponentOf_ifr1_f20.col0 = t_231_E_f20.col1) UNION ALL
  
    SELECT
      t_275_E_f20.col0 AS col0,
      t_275_E_f20.col0 AS logica_value
    FROM
      t_186_E_f20 AS t_275_E_f20
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f9_f20.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f9_f20.logica_value) AS logica_value
FROM
  t_230_ComponentOf_MultBodyAggAux_f9_f20 AS ComponentOf_MultBodyAggAux_f9_f20
GROUP BY ComponentOf_MultBodyAggAux_f9_f20.col0;

-- Interacting with table logica_home.ComponentOf_ifr2_f20

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr3_f20 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr3_f20 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_216_ComponentOf_MultBodyAggAux_f10_f20 AS (SELECT * FROM (
  
    SELECT
      t_217_E_f20.col0 AS col0,
      ComponentOf_ifr2_f20.logica_value AS logica_value
    FROM
      t_186_E_f20 AS t_217_E_f20, logica_home.ComponentOf_ifr2_f20 AS ComponentOf_ifr2_f20
    WHERE
      (ComponentOf_ifr2_f20.col0 = t_217_E_f20.col1) UNION ALL
  
    SELECT
      t_276_E_f20.col0 AS col0,
      t_276_E_f20.col0 AS logica_value
    FROM
      t_186_E_f20 AS t_276_E_f20
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f10_f20.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f10_f20.logica_value) AS logica_value
FROM
  t_216_ComponentOf_MultBodyAggAux_f10_f20 AS ComponentOf_MultBodyAggAux_f10_f20
GROUP BY ComponentOf_MultBodyAggAux_f10_f20.col0;

-- Interacting with table logica_home.ComponentOf_ifr3_f20

DROP TABLE IF EXISTS logica_home.ComponentOf_ifr2_f20 CASCADE;
CREATE TABLE logica_home.ComponentOf_ifr2_f20 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_202_ComponentOf_MultBodyAggAux_f11_f20 AS (SELECT * FROM (
  
    SELECT
      t_203_E_f20.col0 AS col0,
      ComponentOf_ifr3_f20.logica_value AS logica_value
    FROM
      t_186_E_f20 AS t_203_E_f20, logica_home.ComponentOf_ifr3_f20 AS ComponentOf_ifr3_f20
    WHERE
      (ComponentOf_ifr3_f20.col0 = t_203_E_f20.col1) UNION ALL
  
    SELECT
      t_277_E_f20.col0 AS col0,
      t_277_E_f20.col0 AS logica_value
    FROM
      t_186_E_f20 AS t_277_E_f20
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f11_f20.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f11_f20.logica_value) AS logica_value
FROM
  t_202_ComponentOf_MultBodyAggAux_f11_f20 AS ComponentOf_MultBodyAggAux_f11_f20
GROUP BY ComponentOf_MultBodyAggAux_f11_f20.col0;

-- Interacting with table logica_home.ComponentOf_ifr2_f20

DROP TABLE IF EXISTS logica_home.ComponentOf_f20 CASCADE;
CREATE TABLE logica_home.ComponentOf_f20 AS WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_184_ComponentOf_MultBodyAggAux_f12_f20 AS (SELECT * FROM (
  
    SELECT
      t_185_E_f20.col0 AS col0,
      ComponentOf_ifr4_f20.logica_value AS logica_value
    FROM
      t_186_E_f20 AS t_185_E_f20, logica_home.ComponentOf_ifr2_f20 AS ComponentOf_ifr4_f20
    WHERE
      (ComponentOf_ifr4_f20.col0 = t_185_E_f20.col1) UNION ALL
  
    SELECT
      t_278_E_f20.col0 AS col0,
      t_278_E_f20.col0 AS logica_value
    FROM
      t_186_E_f20 AS t_278_E_f20
) AS UNUSED_TABLE_NAME  )
SELECT
  ComponentOf_MultBodyAggAux_f12_f20.col0 AS col0,
  MIN(ComponentOf_MultBodyAggAux_f12_f20.logica_value) AS logica_value
FROM
  t_184_ComponentOf_MultBodyAggAux_f12_f20 AS ComponentOf_MultBodyAggAux_f12_f20
GROUP BY ComponentOf_MultBodyAggAux_f12_f20.col0;

-- Interacting with table logica_home.ComponentOf_f20

DROP TABLE IF EXISTS logica_home.Color_ifr0_f20 CASCADE;
CREATE TABLE logica_home.Color_ifr0_f20 AS WITH t_183_ComponentStart_f20 AS (SELECT
  ComponentOf_f20.logica_value AS logica_value
FROM
  logica_home.ComponentOf_f20 AS ComponentOf_f20
GROUP BY ComponentOf_f20.logica_value),
t_349_Color_MultBodyAggAux_f14_f20 AS (SELECT * FROM (
  
    SELECT
      t_350_ComponentStart_f20.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_183_ComponentStart_f20 AS t_350_ComponentStart_f20
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f14_f20.col0 AS col0,
  Color_MultBodyAggAux_f14_f20.logica_value AS logica_value
FROM
  t_349_Color_MultBodyAggAux_f14_f20 AS Color_MultBodyAggAux_f14_f20
GROUP BY Color_MultBodyAggAux_f14_f20.col0, Color_MultBodyAggAux_f14_f20.logica_value;

-- Interacting with table logica_home.Color_ifr0_f20

DROP TABLE IF EXISTS logica_home.Color_ifr1_f20 CASCADE;
CREATE TABLE logica_home.Color_ifr1_f20 AS WITH t_183_ComponentStart_f20 AS (SELECT
  ComponentOf_f20.logica_value AS logica_value
FROM
  logica_home.ComponentOf_f20 AS ComponentOf_f20
GROUP BY ComponentOf_f20.logica_value),
t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_156_Other AS (SELECT * FROM (
  
    SELECT
      '#eee' AS col0,
      '#bbb' AS logica_value UNION ALL
  
    SELECT
      '#bbb' AS col0,
      '#eee' AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_331_Color_MultBodyAggAux_f15_f20 AS (SELECT * FROM (
  
    SELECT
      t_332_ComponentStart_f20.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_183_ComponentStart_f20 AS t_332_ComponentStart_f20 UNION ALL
  
    SELECT
      t_335_E_f20.col1 AS col0,
      t_336_Other.logica_value AS logica_value
    FROM
      t_186_E_f20 AS t_335_E_f20, logica_home.Color_ifr0_f20 AS Color_ifr0_f20, t_156_Other AS t_336_Other
    WHERE
      (Color_ifr0_f20.col0 = t_335_E_f20.col0) AND
      (t_336_Other.col0 = Color_ifr0_f20.logica_value)
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f15_f20.col0 AS col0,
  Color_MultBodyAggAux_f15_f20.logica_value AS logica_value
FROM
  t_331_Color_MultBodyAggAux_f15_f20 AS Color_MultBodyAggAux_f15_f20
GROUP BY Color_MultBodyAggAux_f15_f20.col0, Color_MultBodyAggAux_f15_f20.logica_value;

-- Interacting with table logica_home.Color_ifr1_f20

DROP TABLE IF EXISTS logica_home.Color_ifr2_f20 CASCADE;
CREATE TABLE logica_home.Color_ifr2_f20 AS WITH t_183_ComponentStart_f20 AS (SELECT
  ComponentOf_f20.logica_value AS logica_value
FROM
  logica_home.ComponentOf_f20 AS ComponentOf_f20
GROUP BY ComponentOf_f20.logica_value),
t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_156_Other AS (SELECT * FROM (
  
    SELECT
      '#eee' AS col0,
      '#bbb' AS logica_value UNION ALL
  
    SELECT
      '#bbb' AS col0,
      '#eee' AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_313_Color_MultBodyAggAux_f16_f20 AS (SELECT * FROM (
  
    SELECT
      t_314_ComponentStart_f20.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_183_ComponentStart_f20 AS t_314_ComponentStart_f20 UNION ALL
  
    SELECT
      t_317_E_f20.col1 AS col0,
      t_318_Other.logica_value AS logica_value
    FROM
      t_186_E_f20 AS t_317_E_f20, logica_home.Color_ifr1_f20 AS Color_ifr1_f20, t_156_Other AS t_318_Other
    WHERE
      (Color_ifr1_f20.col0 = t_317_E_f20.col0) AND
      (t_318_Other.col0 = Color_ifr1_f20.logica_value)
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f16_f20.col0 AS col0,
  Color_MultBodyAggAux_f16_f20.logica_value AS logica_value
FROM
  t_313_Color_MultBodyAggAux_f16_f20 AS Color_MultBodyAggAux_f16_f20
GROUP BY Color_MultBodyAggAux_f16_f20.col0, Color_MultBodyAggAux_f16_f20.logica_value;

-- Interacting with table logica_home.Color_ifr2_f20

DROP TABLE IF EXISTS logica_home.Color_ifr1_f20 CASCADE;
CREATE TABLE logica_home.Color_ifr1_f20 AS WITH t_183_ComponentStart_f20 AS (SELECT
  ComponentOf_f20.logica_value AS logica_value
FROM
  logica_home.ComponentOf_f20 AS ComponentOf_f20
GROUP BY ComponentOf_f20.logica_value),
t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_156_Other AS (SELECT * FROM (
  
    SELECT
      '#eee' AS col0,
      '#bbb' AS logica_value UNION ALL
  
    SELECT
      '#bbb' AS col0,
      '#eee' AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_295_Color_MultBodyAggAux_f17_f20 AS (SELECT * FROM (
  
    SELECT
      t_296_ComponentStart_f20.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_183_ComponentStart_f20 AS t_296_ComponentStart_f20 UNION ALL
  
    SELECT
      t_299_E_f20.col1 AS col0,
      t_300_Other.logica_value AS logica_value
    FROM
      t_186_E_f20 AS t_299_E_f20, logica_home.Color_ifr2_f20 AS Color_ifr2_f20, t_156_Other AS t_300_Other
    WHERE
      (Color_ifr2_f20.col0 = t_299_E_f20.col0) AND
      (t_300_Other.col0 = Color_ifr2_f20.logica_value)
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f17_f20.col0 AS col0,
  Color_MultBodyAggAux_f17_f20.logica_value AS logica_value
FROM
  t_295_Color_MultBodyAggAux_f17_f20 AS Color_MultBodyAggAux_f17_f20
GROUP BY Color_MultBodyAggAux_f17_f20.col0, Color_MultBodyAggAux_f17_f20.logica_value;

-- Interacting with table logica_home.Color_ifr1_f20

DROP TABLE IF EXISTS logica_home.Color_f20 CASCADE;
CREATE TABLE logica_home.Color_f20 AS WITH t_183_ComponentStart_f20 AS (SELECT
  ComponentOf_f20.logica_value AS logica_value
FROM
  logica_home.ComponentOf_f20 AS ComponentOf_f20
GROUP BY ComponentOf_f20.logica_value),
t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  ),
t_156_Other AS (SELECT * FROM (
  
    SELECT
      '#eee' AS col0,
      '#bbb' AS logica_value UNION ALL
  
    SELECT
      '#bbb' AS col0,
      '#eee' AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_181_Color_MultBodyAggAux_f18_f20 AS (SELECT * FROM (
  
    SELECT
      ComponentStart_f20.logica_value AS col0,
      '#eee' AS logica_value
    FROM
      t_183_ComponentStart_f20 AS ComponentStart_f20 UNION ALL
  
    SELECT
      t_281_E_f20.col1 AS col0,
      t_282_Other.logica_value AS logica_value
    FROM
      t_186_E_f20 AS t_281_E_f20, logica_home.Color_ifr1_f20 AS Color_ifr3_f20, t_156_Other AS t_282_Other
    WHERE
      (Color_ifr3_f20.col0 = t_281_E_f20.col0) AND
      (t_282_Other.col0 = Color_ifr3_f20.logica_value)
) AS UNUSED_TABLE_NAME  )
SELECT
  Color_MultBodyAggAux_f18_f20.col0 AS col0,
  Color_MultBodyAggAux_f18_f20.logica_value AS logica_value
FROM
  t_181_Color_MultBodyAggAux_f18_f20 AS Color_MultBodyAggAux_f18_f20
GROUP BY Color_MultBodyAggAux_f18_f20.col0, Color_MultBodyAggAux_f18_f20.logica_value;

-- Interacting with table logica_home.Color_f20

WITH t_5_G AS (SELECT * FROM (
  
    SELECT
      ((CAST('a' AS TEXT) || ':') || CAST(x_43 AS TEXT)) AS col0,
      ((CAST('a' AS TEXT) || ':') || CAST(((x_43) + (1)) AS TEXT)) AS col1
    FROM
      UNNEST((SELECT ARRAY_AGG(x) FROM GENERATE_SERIES(0, 6 - 1) as x)) as x_43 UNION ALL
  
    SELECT
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col0 AS TEXT)) AS TEXT) || ':') || CAST(L.col1 AS TEXT)) AS col0,
      ((CAST(((CAST('b' AS TEXT) || ':') || CAST(L.col2 AS TEXT)) AS TEXT) || ':') || CAST(L.col3 AS TEXT)) AS col1
    FROM
      logica_home.L AS L
    WHERE
      (L.col0 < 6) AND
      (L.col1 < 6)
) AS UNUSED_TABLE_NAME  ),
t_4_E AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_5_G AS G UNION ALL
  
    SELECT
      t_22_G.col1 AS col0,
      t_22_G.col0 AS col1
    FROM
      t_5_G AS t_22_G
) AS UNUSED_TABLE_NAME  ),
t_187_G2 AS (SELECT * FROM (
  
    SELECT
      t_188_G.col0 AS col0,
      t_188_G.col1 AS col1
    FROM
      t_5_G AS t_188_G UNION ALL
  
    SELECT
      'a:0' AS col0,
      'a:6' AS col1
) AS UNUSED_TABLE_NAME  ),
t_186_E_f20 AS (SELECT * FROM (
  
    SELECT
      G2.col0 AS col0,
      G2.col1 AS col1
    FROM
      t_187_G2 AS G2 UNION ALL
  
    SELECT
      t_198_G2.col1 AS col0,
      t_198_G2.col0 AS col1
    FROM
      t_187_G2 AS t_198_G2
) AS UNUSED_TABLE_NAME  )
SELECT * FROM (
  
    SELECT
      'G1' AS col0,
      CASE WHEN (CAST((SELECT
      MAX((CASE WHEN x_6 = 0 THEN CAST((SELECT
      COUNT(DISTINCT (CASE WHEN x_9 = 0 THEN Color.logica_value ELSE NULL END)) AS logica_value
    FROM
      logica_home.Color AS Color, UNNEST(ARRAY[0]::numeric[]) as x_9
    WHERE
      (Color.col0 = E.col0)) AS numeric) ELSE NULL END)) AS logica_value
    FROM
      t_4_E AS E, UNNEST(ARRAY[0]::numeric[]) as x_6) AS numeric) = 1) THEN 'colorable' ELSE 'not colorable' END AS col1 UNION ALL
  
    SELECT
      'G2' AS col0,
      CASE WHEN (CAST((SELECT
      MAX((CASE WHEN x_1005 = 0 THEN CAST((SELECT
      COUNT(DISTINCT (CASE WHEN x_1008 = 0 THEN Color_f20.logica_value ELSE NULL END)) AS logica_value
    FROM
      logica_home.Color_f20 AS Color_f20, UNNEST(ARRAY[0]::numeric[]) as x_1008
    WHERE
      (Color_f20.col0 = E_f20.col0)) AS numeric) ELSE NULL END)) AS logica_value
    FROM
      t_186_E_f20 AS E_f20, UNNEST(ARRAY[0]::numeric[]) as x_1005) AS numeric) = 1) THEN 'colorable' ELSE 'not colorable' END AS col1
) AS UNUSED_TABLE_NAME  ORDER BY col0 ;
