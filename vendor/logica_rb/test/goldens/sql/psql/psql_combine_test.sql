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
END $$;
WITH t_1_T AS (SELECT * FROM (
  
    SELECT
      1 AS col0 UNION ALL
  
    SELECT
      2 AS col0 UNION ALL
  
    SELECT
      3 AS col0 UNION ALL
  
    SELECT
      4 AS col0
) AS UNUSED_TABLE_NAME  ),
t_6_R AS (SELECT
  t_7_T.col0 AS col0,
  CASE WHEN ((t_7_T.col0 = 2) OR (t_7_T.col0 = 3)) THEN ARRAY[t_7_T.col0]::numeric[] ELSE ARRAY[]::numeric[] END AS col1
FROM
  t_1_T AS t_7_T),
t_2_P2 AS (SELECT
  t_3_T.col0 AS col0,
  ARRAY_AGG(x_29 order by x_29) AS col1
FROM
  t_1_T AS t_3_T, t_6_R AS R, UNNEST(ARRAY[1, 2, 3, 4]::numeric[]) as x_29
WHERE
  (CAST((SELECT
    MIN((CASE WHEN x_45 = 0 THEN 1 ELSE NULL END)) AS logica_value
  FROM
    UNNEST(R.col1) as x_44, UNNEST(ARRAY[0]::numeric[]) as x_45
  WHERE
    (x_29 = x_44)) AS numeric) IS NULL) AND
  (R.col0 = t_3_T.col0)
GROUP BY t_3_T.col0)
SELECT * FROM (
  
    SELECT
      'test1' AS col0,
      T.col0 AS col1,
      CAST((SELECT
      ARRAY_AGG(((CASE WHEN x_11 = 0 THEN ROW(T.col0, T.col0)::logicarecord884343024 ELSE NULL END)).value order by ((CASE WHEN x_11 = 0 THEN ROW(T.col0, T.col0)::logicarecord884343024 ELSE NULL END)).arg) AS logica_value
    FROM
      UNNEST(ARRAY[0]::numeric[]) as x_11) AS numeric[]) AS col2
    FROM
      t_1_T AS T UNION ALL
  
    SELECT
      'test2' AS col0,
      P2.col0 AS col1,
      P2.col1 AS col2
    FROM
      t_2_P2 AS P2
) AS UNUSED_TABLE_NAME  ORDER BY col0, col1 ;
