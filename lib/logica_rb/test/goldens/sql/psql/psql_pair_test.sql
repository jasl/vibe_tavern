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
-- Logica type: logicarecord929842458
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord929842458') then create type logicarecord929842458 as (length numeric, word text); end if;
-- Logica type: logicarecord615622689
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord615622689') then create type logicarecord615622689 as (arg numeric, value logicarecord929842458); end if;
END $$;
WITH t_1_Word AS (SELECT * FROM (
  
    SELECT
      'fire' AS col0 UNION ALL
  
    SELECT
      'water' AS col0 UNION ALL
  
    SELECT
      'wind' AS col0 UNION ALL
  
    SELECT
      'sun' AS col0
) AS UNUSED_TABLE_NAME  )
SELECT
  ARRAY_AGG(ROW(LENGTH(Word.col0), Word.col0)::logicarecord929842458 order by LENGTH(Word.col0)) AS logica_value
FROM
  t_1_Word AS Word;
