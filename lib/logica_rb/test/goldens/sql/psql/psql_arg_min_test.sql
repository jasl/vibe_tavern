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
-- Logica type: logicarecord462007516
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord462007516') then create type logicarecord462007516 as (argpod text); end if;
-- Logica type: logicarecord183863755
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord183863755') then create type logicarecord183863755 as (arg text, value numeric); end if;
-- Logica type: logicarecord68214556
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord68214556') then create type logicarecord68214556 as (arg logicarecord462007516, value numeric); end if;
END $$;
WITH t_1_Employee AS (SELECT * FROM (
  
    SELECT
      'Eng' AS dep,
      'John' AS name,
      8 AS vacation_days UNION ALL
  
    SELECT
      'Eng' AS dep,
      'James' AS name,
      4 AS vacation_days UNION ALL
  
    SELECT
      'Eng' AS dep,
      'Matthew' AS name,
      2 AS vacation_days UNION ALL
  
    SELECT
      'Eng' AS dep,
      'Jeremy' AS name,
      5 AS vacation_days UNION ALL
  
    SELECT
      'Sales' AS dep,
      'Evan' AS name,
      7 AS vacation_days
) AS UNUSED_TABLE_NAME  )
SELECT
  Employee.dep AS dep,
  ((ARRAY_AGG(ROW(Employee.name)::logicarecord462007516 order by Employee.vacation_days))[1]).argpod AS person
FROM
  t_1_Employee AS Employee
GROUP BY Employee.dep;
