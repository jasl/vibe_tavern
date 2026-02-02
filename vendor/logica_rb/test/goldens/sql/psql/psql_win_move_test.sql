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
-- Logica type: logicarecord657281595
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord657281595') then create type logicarecord657281595 as (col0 text); end if;
END $$;
WITH t_0_Move AS (SELECT * FROM (
  
    SELECT
      'a' AS col0,
      'b' AS col1 UNION ALL
  
    SELECT
      'b' AS col0,
      'a' AS col1 UNION ALL
  
    SELECT
      'b' AS col0,
      'c' AS col1 UNION ALL
  
    SELECT
      'c' AS col0,
      'd' AS col1
) AS UNUSED_TABLE_NAME  )
SELECT
  (ROW(Move.col0)::logicarecord657281595).*
FROM
  t_0_Move AS Move
WHERE
  (CAST((SELECT
    MIN((CASE WHEN x_10 = 0 THEN 1 ELSE NULL END)) AS logica_value
  FROM
    t_0_Move AS t_1_Move, UNNEST(ARRAY[0]::numeric[]) as x_10
  WHERE
    (CAST((SELECT
      MIN((CASE WHEN x_16 = 0 THEN 1 ELSE NULL END)) AS logica_value
    FROM
      t_0_Move AS t_2_Move, UNNEST(ARRAY[0]::numeric[]) as x_16
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_22 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        t_0_Move AS t_3_Move, UNNEST(ARRAY[0]::numeric[]) as x_22
      WHERE
        (CAST((SELECT
          MIN((CASE WHEN x_28 = 0 THEN 1 ELSE NULL END)) AS logica_value
        FROM
          t_0_Move AS t_4_Move, UNNEST(ARRAY[0]::numeric[]) as x_28
        WHERE
          (CAST((SELECT
            MIN((CASE WHEN x_34 = 0 THEN 1 ELSE NULL END)) AS logica_value
          FROM
            t_0_Move AS t_5_Move, UNNEST(ARRAY[0]::numeric[]) as x_34
          WHERE
            (CAST((SELECT
              MIN((CASE WHEN x_40 = 0 THEN 1 ELSE NULL END)) AS logica_value
            FROM
              t_0_Move AS t_6_Move, UNNEST(ARRAY[0]::numeric[]) as x_40
            WHERE
              (CAST((SELECT
                MIN((CASE WHEN x_46 = 0 THEN 1 ELSE NULL END)) AS logica_value
              FROM
                t_0_Move AS t_7_Move, UNNEST(ARRAY[0]::numeric[]) as x_46
              WHERE
                (CAST((SELECT
                  MIN((CASE WHEN x_52 = 0 THEN 1 ELSE NULL END)) AS logica_value
                FROM
                  t_0_Move AS t_8_Move, UNNEST(ARRAY[0]::numeric[]) as x_52
                WHERE
                  (CAST((/* nil */ SELECT NULL FROM (SELECT 42 AS MONAD) AS NIRVANA WHERE MONAD = 0) AS numeric) IS NULL) AND
                  (t_7_Move.col1 = t_8_Move.col0)) AS numeric) IS NULL) AND
                (t_6_Move.col1 = t_7_Move.col0)) AS numeric) IS NULL) AND
              (t_5_Move.col1 = t_6_Move.col0)) AS numeric) IS NULL) AND
            (t_4_Move.col1 = t_5_Move.col0)) AS numeric) IS NULL) AND
          (t_3_Move.col1 = t_4_Move.col0)) AS numeric) IS NULL) AND
        (t_2_Move.col1 = t_3_Move.col0)) AS numeric) IS NULL) AND
      (t_1_Move.col1 = t_2_Move.col0)) AS numeric) IS NULL) AND
    (Move.col1 = t_1_Move.col0)) AS numeric) IS NULL) AND
  (true = NOT (CAST((SELECT
    MIN((CASE WHEN x_61 = 0 THEN 1 ELSE NULL END)) AS logica_value
  FROM
    t_0_Move AS t_10_Move, UNNEST(ARRAY[0]::numeric[]) as x_61
  WHERE
    (CAST((SELECT
      MIN((CASE WHEN x_67 = 0 THEN 1 ELSE NULL END)) AS logica_value
    FROM
      t_0_Move AS t_12_Move, UNNEST(ARRAY[0]::numeric[]) as x_67
    WHERE
      (CAST((SELECT
        MIN((CASE WHEN x_73 = 0 THEN 1 ELSE NULL END)) AS logica_value
      FROM
        t_0_Move AS t_14_Move, UNNEST(ARRAY[0]::numeric[]) as x_73
      WHERE
        (CAST((SELECT
          MIN((CASE WHEN x_79 = 0 THEN 1 ELSE NULL END)) AS logica_value
        FROM
          t_0_Move AS t_16_Move, UNNEST(ARRAY[0]::numeric[]) as x_79
        WHERE
          (CAST((SELECT
            MIN((CASE WHEN x_85 = 0 THEN 1 ELSE NULL END)) AS logica_value
          FROM
            t_0_Move AS t_18_Move, UNNEST(ARRAY[0]::numeric[]) as x_85
          WHERE
            (CAST((SELECT
              MIN((CASE WHEN x_91 = 0 THEN 1 ELSE NULL END)) AS logica_value
            FROM
              t_0_Move AS t_20_Move, UNNEST(ARRAY[0]::numeric[]) as x_91
            WHERE
              (CAST((SELECT
                MIN((CASE WHEN x_97 = 0 THEN 1 ELSE NULL END)) AS logica_value
              FROM
                t_0_Move AS t_22_Move, UNNEST(ARRAY[0]::numeric[]) as x_97
              WHERE
                (CAST((SELECT
                  MIN((CASE WHEN x_103 = 0 THEN 1 ELSE NULL END)) AS logica_value
                FROM
                  t_0_Move AS t_24_Move, UNNEST(ARRAY[0]::numeric[]) as x_103
                WHERE
                  (CAST((/* nil */ SELECT NULL FROM (SELECT 42 AS MONAD) AS NIRVANA WHERE MONAD = 0) AS numeric) IS NULL) AND
                  (t_22_Move.col1 = t_24_Move.col0)) AS numeric) IS NULL) AND
                (t_20_Move.col1 = t_22_Move.col0)) AS numeric) IS NULL) AND
              (t_18_Move.col1 = t_20_Move.col0)) AS numeric) IS NULL) AND
            (t_16_Move.col1 = t_18_Move.col0)) AS numeric) IS NULL) AND
          (t_14_Move.col1 = t_16_Move.col0)) AS numeric) IS NULL) AND
        (t_12_Move.col1 = t_14_Move.col0)) AS numeric) IS NULL) AND
      (t_10_Move.col1 = t_12_Move.col0)) AS numeric) IS NULL) AND
    (Move.col0 = t_10_Move.col0)) AS numeric) IS NULL));
