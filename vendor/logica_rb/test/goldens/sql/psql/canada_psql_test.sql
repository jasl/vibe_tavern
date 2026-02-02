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
WITH t_1_Canada_ProductCanada AS (SELECT * FROM (
  
    SELECT
      'milk' AS col0,
      10 AS price UNION ALL
  
    SELECT
      'oil' AS col0,
      150 AS price UNION ALL
  
    SELECT
      'doctors' AS col0,
      500 AS price
) AS UNUSED_TABLE_NAME  ),
t_2_Usa_ProductUSA AS (SELECT * FROM (
  
    SELECT
      'software' AS col0,
      50 AS price UNION ALL
  
    SELECT
      'movies' AS col0,
      100 AS price UNION ALL
  
    SELECT
      'grain' AS col0,
      2 AS price
) AS UNUSED_TABLE_NAME  ),
t_0_Canada_Consume AS (SELECT * FROM (
  
    SELECT
      Canada_ProductCanada.col0 AS col0
    FROM
      t_1_Canada_ProductCanada AS Canada_ProductCanada UNION ALL
  
    SELECT
      Usa_ProductUSA.col0 AS col0
    FROM
      t_2_Usa_ProductUSA AS Usa_ProductUSA
) AS UNUSED_TABLE_NAME  ORDER BY col0 )
SELECT
  (Canada_Consume).*
FROM
  t_0_Canada_Consume AS Canada_Consume ORDER BY col0;
