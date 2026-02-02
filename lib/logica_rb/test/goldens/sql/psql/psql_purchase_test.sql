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
-- Logica type: logicarecord547335026
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord547335026') then create type logicarecord547335026 as (item text, price numeric, quantity numeric); end if;
-- Logica type: logicarecord672603333
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord672603333') then create type logicarecord672603333 as (item text, more_expensive_than text[]); end if;
-- Logica type: logicarecord699137742
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord699137742') then create type logicarecord699137742 as (arg text, value logicarecord547335026); end if;
-- Logica type: logicarecord851083403
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord851083403') then create type logicarecord851083403 as (arg logicarecord672603333, value logicarecord672603333); end if;
-- Logica type: logicarecord251409195
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord251409195') then create type logicarecord251409195 as (buyer_id numeric, expensive_items logicarecord672603333[], items logicarecord547335026[], purchase_id numeric); end if;
END $$;
WITH t_2_BuyEvent AS (SELECT * FROM (
  
    SELECT
      1 AS purchase_id,
      'Soap' AS item,
      3 AS quantity UNION ALL
  
    SELECT
      2 AS purchase_id,
      'Milk' AS item,
      1 AS quantity UNION ALL
  
    SELECT
      3 AS purchase_id,
      'Bread' AS item,
      2 AS quantity UNION ALL
  
    SELECT
      3 AS purchase_id,
      'Coffee' AS item,
      1 AS quantity UNION ALL
  
    SELECT
      4 AS purchase_id,
      'Firewood' AS item,
      5 AS quantity UNION ALL
  
    SELECT
      4 AS purchase_id,
      'Soap' AS item,
      1 AS quantity UNION ALL
  
    SELECT
      5 AS purchase_id,
      'Milk' AS item,
      4 AS quantity UNION ALL
  
    SELECT
      5 AS purchase_id,
      'Bread' AS item,
      1 AS quantity UNION ALL
  
    SELECT
      5 AS purchase_id,
      'Coffee' AS item,
      2 AS quantity UNION ALL
  
    SELECT
      6 AS purchase_id,
      'Firewood' AS item,
      1 AS quantity UNION ALL
  
    SELECT
      6 AS purchase_id,
      'Soap' AS item,
      3 AS quantity UNION ALL
  
    SELECT
      7 AS purchase_id,
      'Milk' AS item,
      1 AS quantity UNION ALL
  
    SELECT
      7 AS purchase_id,
      'Bread' AS item,
      2 AS quantity UNION ALL
  
    SELECT
      7 AS purchase_id,
      'Coffee' AS item,
      1 AS quantity UNION ALL
  
    SELECT
      8 AS purchase_id,
      'Firewood' AS item,
      5 AS quantity UNION ALL
  
    SELECT
      8 AS purchase_id,
      'Soap' AS item,
      1 AS quantity
) AS UNUSED_TABLE_NAME  ),
t_3_Items AS (SELECT * FROM (
  
    SELECT
      'Soap' AS item,
      20 AS price UNION ALL
  
    SELECT
      'Milk' AS item,
      10 AS price UNION ALL
  
    SELECT
      'Bread' AS item,
      5 AS price UNION ALL
  
    SELECT
      'Coffee' AS item,
      7 AS price UNION ALL
  
    SELECT
      'Firewood' AS item,
      15 AS price
) AS UNUSED_TABLE_NAME  ),
t_8_MoreExpensiveThan AS (SELECT
  t_9_Items.item AS col0,
  ARRAY_AGG(t_10_Items.item order by t_10_Items.item) AS logica_value
FROM
  t_3_Items AS t_9_Items, t_3_Items AS t_10_Items
WHERE
  (t_9_Items.price > t_10_Items.price)
GROUP BY t_9_Items.item),
t_17_Buyer AS (SELECT * FROM (
  
    SELECT
      11 AS buyer_id,
      1 AS purchase_id UNION ALL
  
    SELECT
      12 AS buyer_id,
      2 AS purchase_id UNION ALL
  
    SELECT
      13 AS buyer_id,
      3 AS purchase_id UNION ALL
  
    SELECT
      14 AS buyer_id,
      4 AS purchase_id UNION ALL
  
    SELECT
      12 AS buyer_id,
      5 AS purchase_id UNION ALL
  
    SELECT
      13 AS buyer_id,
      6 AS purchase_id UNION ALL
  
    SELECT
      14 AS buyer_id,
      7 AS purchase_id UNION ALL
  
    SELECT
      11 AS buyer_id,
      8 AS purchase_id
) AS UNUSED_TABLE_NAME  ),
t_0_Purchase AS (SELECT
  Buyer.purchase_id AS purchase_id,
  CAST((SELECT
  ARRAY_AGG(((CASE WHEN x_23 = 0 THEN ROW(BuyEvent.item, ROW(BuyEvent.item, Items.price, BuyEvent.quantity)::logicarecord547335026)::logicarecord699137742 ELSE NULL END)).value order by ((CASE WHEN x_23 = 0 THEN ROW(BuyEvent.item, ROW(BuyEvent.item, Items.price, BuyEvent.quantity)::logicarecord547335026)::logicarecord699137742 ELSE NULL END)).arg) AS logica_value
FROM
  t_2_BuyEvent AS BuyEvent, t_3_Items AS Items, UNNEST(ARRAY[0]::numeric[]) as x_23
WHERE
  (BuyEvent.purchase_id = Buyer.purchase_id) AND
  (Items.item = BuyEvent.item)) AS logicarecord547335026[]) AS items,
  CAST((SELECT
  ARRAY_AGG(((CASE WHEN x_42 = 0 THEN ROW(ROW(MoreExpensiveThan.col0, MoreExpensiveThan.logica_value)::logicarecord672603333, ROW(MoreExpensiveThan.col0, MoreExpensiveThan.logica_value)::logicarecord672603333)::logicarecord851083403 ELSE NULL END)).value order by ((CASE WHEN x_42 = 0 THEN ROW(ROW(MoreExpensiveThan.col0, MoreExpensiveThan.logica_value)::logicarecord672603333, ROW(MoreExpensiveThan.col0, MoreExpensiveThan.logica_value)::logicarecord672603333)::logicarecord851083403 ELSE NULL END)).arg) AS logica_value
FROM
  t_8_MoreExpensiveThan AS MoreExpensiveThan, UNNEST(CAST((SELECT
    ARRAY_AGG(((CASE WHEN x_84 = 0 THEN ROW(t_13_BuyEvent.item, ROW(t_13_BuyEvent.item, t_14_Items.price, t_13_BuyEvent.quantity)::logicarecord547335026)::logicarecord699137742 ELSE NULL END)).value order by ((CASE WHEN x_84 = 0 THEN ROW(t_13_BuyEvent.item, ROW(t_13_BuyEvent.item, t_14_Items.price, t_13_BuyEvent.quantity)::logicarecord547335026)::logicarecord699137742 ELSE NULL END)).arg) AS logica_value
  FROM
    t_2_BuyEvent AS t_13_BuyEvent, t_3_Items AS t_14_Items, UNNEST(ARRAY[0]::numeric[]) as x_84
  WHERE
    (t_13_BuyEvent.purchase_id = Buyer.purchase_id) AND
    (t_14_Items.item = t_13_BuyEvent.item)) AS logicarecord547335026[])) as x_39, UNNEST(ARRAY[0]::numeric[]) as x_42
WHERE
  (MoreExpensiveThan.col0 = (x_39).item)) AS logicarecord672603333[]) AS expensive_items,
  Buyer.buyer_id AS buyer_id
FROM
  t_17_Buyer AS Buyer ORDER BY purchase_id, items, expensive_items, buyer_id)
SELECT
  (Purchase).*
FROM
  t_0_Purchase AS Purchase;
