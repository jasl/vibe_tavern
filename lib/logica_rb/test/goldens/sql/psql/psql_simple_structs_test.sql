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
-- Logica type: logicarecord973267234
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord973267234') then create type logicarecord973267234 as (a text); end if;
-- Logica type: logicarecord137760342
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord137760342') then create type logicarecord137760342 as (c numeric[]); end if;
-- Logica type: logicarecord121724557
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord121724557') then create type logicarecord121724557 as (c numeric, d numeric); end if;
-- Logica type: logicarecord884343024
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord884343024') then create type logicarecord884343024 as (arg numeric, value numeric); end if;
-- Logica type: logicarecord202107459
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord202107459') then create type logicarecord202107459 as (a numeric, b logicarecord137760342, c logicarecord973267234); end if;
-- Logica type: logicarecord149134143
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord149134143') then create type logicarecord149134143 as (a numeric, b logicarecord121724557, some_field numeric); end if;
END $$;
SELECT
  ROW(x_2, x_3)::logicarecord884343024 AS col0,
  ROW(x_2, ROW(ARRAY[x_2, x_3]::numeric[])::logicarecord137760342, x_4)::logicarecord202107459 AS col1,
  ROW(x_2, ROW(x_2, x_3)::logicarecord121724557, ((x_2) + (x_3)))::logicarecord149134143 AS col2
FROM
  UNNEST(ARRAY[1, 2]::numeric[]) as x_2, UNNEST(ARRAY[3, 4]::numeric[]) as x_3, UNNEST(ARRAY[ROW('abc')::logicarecord973267234, ROW('def')::logicarecord973267234]::logicarecord973267234[]) as x_4;
