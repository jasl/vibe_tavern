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
-- Logica type: logicarecord547335026
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord547335026') then create type logicarecord547335026 as (item text, price numeric, quantity numeric); end if;
-- Logica type: logicarecord672603333
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord672603333') then create type logicarecord672603333 as (item text, more_expensive_than text[]); end if;
-- Logica type: logicarecord839295167
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord839295167') then create type logicarecord839295167 as (purchase logicarecord547335026[]); end if;
END $$;
WITH t_1_BuyEvent AS (SELECT * FROM (
  
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
t_2_Items AS (SELECT * FROM (
  
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
t_4_MoreExpensiveThan AS (SELECT
  t_5_Items.item AS col0,
  ARRAY_AGG(t_6_Items.item) AS logica_value
FROM
  t_2_Items AS t_5_Items, t_2_Items AS t_6_Items
WHERE
  (t_5_Items.price > t_6_Items.price)
GROUP BY t_5_Items.item),
t_9_Buyer AS (SELECT * FROM (
  
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
  ARRAY_AGG((CASE WHEN x_26 = 0 THEN ROW(BuyEvent.item, Items.price, BuyEvent.quantity)::logicarecord547335026 ELSE NULL END)) AS logica_value
FROM
  t_1_BuyEvent AS BuyEvent, t_2_Items AS Items, UNNEST(ARRAY[0]::numeric[]) as x_26
WHERE
  (BuyEvent.purchase_id = Buyer.purchase_id) AND
  (Items.item = BuyEvent.item)) AS logicarecord547335026[]) AS items,
  CAST((SELECT
  ARRAY_AGG((CASE WHEN x_32 = 0 THEN ROW(MoreExpensiveThan.col0, MoreExpensiveThan.logica_value)::logicarecord672603333 ELSE NULL END)) AS logica_value
FROM
  t_4_MoreExpensiveThan AS MoreExpensiveThan, UNNEST(CAST((SELECT
    ARRAY_AGG((CASE WHEN x_49 = 0 THEN ROW(t_7_BuyEvent.item, t_8_Items.price, t_7_BuyEvent.quantity)::logicarecord547335026 ELSE NULL END)) AS logica_value
  FROM
    t_1_BuyEvent AS t_7_BuyEvent, t_2_Items AS t_8_Items, UNNEST(ARRAY[0]::numeric[]) as x_49
  WHERE
    (t_7_BuyEvent.purchase_id = Buyer.purchase_id) AND
    (t_8_Items.item = t_7_BuyEvent.item)) AS logicarecord547335026[])) as x_29, UNNEST(ARRAY[0]::numeric[]) as x_32
WHERE
  (MoreExpensiveThan.col0 = (x_29).item)) AS logicarecord672603333[]) AS expensive_items,
  Buyer.buyer_id AS buyer_id
FROM
  t_9_Buyer AS Buyer ORDER BY purchase_id)
SELECT
  x_4 AS buyer_id,
  CAST((SELECT
  ARRAY_AGG((CASE WHEN x_8 = 0 THEN ROW(Purchase.items)::logicarecord839295167 ELSE NULL END)) AS logica_value
FROM
  t_0_Purchase AS Purchase, UNNEST(ARRAY[0]::numeric[]) as x_8
WHERE
  (Purchase.buyer_id = x_4)) AS logicarecord839295167[]) AS purchases
FROM
  UNNEST(CAST((SELECT
    ARRAY_AGG(DISTINCT (CASE WHEN x_52 = 0 THEN t_10_Buyer.buyer_id ELSE NULL END)) AS logica_value
  FROM
    t_9_Buyer AS t_10_Buyer, UNNEST(ARRAY[0]::numeric[]) as x_52) AS numeric[])) as x_4 ORDER BY buyer_id;
