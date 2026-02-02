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
-- Logica type: logicarecord625776357
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord625776357') then create type logicarecord625776357 as (arg text, value text); end if;
END $$;


DROP TABLE IF EXISTS logica_home.Goal CASCADE;
CREATE TABLE logica_home.Goal AS SELECT * FROM (
  
    SELECT
      ROW('human', 'happiness')::logicarecord625776357 AS col0 UNION ALL
  
    SELECT
      ROW('bird', 'flight')::logicarecord625776357 AS col0 UNION ALL
  
    SELECT
      ROW('machine', '?')::logicarecord625776357 AS col0 UNION ALL
  
    SELECT
      ROW('universe', '?')::logicarecord625776357 AS col0
) AS UNUSED_TABLE_NAME  ;

-- Interacting with table logica_home.Goal

SELECT
  (Goal.col0).arg AS col0
FROM
  logica_home.Goal AS Goal
WHERE
  (Goal.col0 = ROW((Goal.col0).arg, '?')::logicarecord625776357) ORDER BY col0;
