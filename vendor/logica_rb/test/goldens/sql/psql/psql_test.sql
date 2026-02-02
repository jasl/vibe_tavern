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
WITH t_0_Parent AS (SELECT * FROM (
  
    SELECT
      'A' AS col0,
      'B' AS col1 UNION ALL
  
    SELECT
      'B' AS col0,
      'C' AS col1 UNION ALL
  
    SELECT
      'C' AS col0,
      'D' AS col1 UNION ALL
  
    SELECT
      'B' AS col0,
      'E' AS col1 UNION ALL
  
    SELECT
      'A' AS col0,
      'F' AS col1 UNION ALL
  
    SELECT
      'A' AS col0,
      'G' AS col1 UNION ALL
  
    SELECT
      'G' AS col0,
      'H' AS col1
) AS UNUSED_TABLE_NAME  ),
t_3_NumChildren AS (SELECT
  t_4_Parent.col0 AS col0,
  SUM(1) AS logica_value
FROM
  t_0_Parent AS t_4_Parent
GROUP BY t_4_Parent.col0),
t_5_ChildrenOf AS (SELECT
  t_6_Parent.col0 AS col0,
  ARRAY_AGG(t_6_Parent.col1) AS logica_value
FROM
  t_0_Parent AS t_6_Parent
GROUP BY t_6_Parent.col0)
SELECT * FROM (
  
    SELECT
      'Parent' AS col0,
      Parent.col0 AS col1,
      Parent.col1 AS col2
    FROM
      t_0_Parent AS Parent UNION ALL
  
    SELECT
      'Grandparent' AS col0,
      t_1_Parent.col0 AS col1,
      t_2_Parent.col1 AS col2
    FROM
      t_0_Parent AS t_1_Parent, t_0_Parent AS t_2_Parent
    WHERE
      (t_2_Parent.col0 = t_1_Parent.col1) UNION ALL
  
    SELECT
      'NumChildren' AS col0,
      NumChildren.col0 AS col1,
      CAST(NumChildren.logica_value AS TEXT) AS col2
    FROM
      t_3_NumChildren AS NumChildren UNION ALL
  
    SELECT
      'ChildrenOf' AS col0,
      ChildrenOf.col0 AS col1,
      ARRAY_TO_STRING(ChildrenOf.logica_value, ',') AS col2
    FROM
      t_5_ChildrenOf AS ChildrenOf
) AS UNUSED_TABLE_NAME  ORDER BY col0, col1, col2 ;
