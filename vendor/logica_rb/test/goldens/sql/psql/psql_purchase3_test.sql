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
-- Logica type: logicarecord839295167
if not exists (select 'I(am) :- I(think)' from pg_type where typname = 'logicarecord839295167') then create type logicarecord839295167 as (purchase logicarecord547335026[]); end if;
END $$;
WITH t_2_Buyer AS (SELECT * FROM (
  
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
t_3_BuyEvent AS (SELECT * FROM (
  
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
t_4_Items AS (SELECT * FROM (
  
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
t_0_Purchase AS (SELECT
  Buyer.purchase_id AS purchase_id,
  ARRAY_AGG(ROW(BuyEvent.item, Items.price, BuyEvent.quantity)::logicarecord547335026) AS items,
  Buyer.buyer_id AS buyer_id
FROM
  t_2_Buyer AS Buyer, t_3_BuyEvent AS BuyEvent, t_4_Items AS Items
WHERE
  (BuyEvent.purchase_id = Buyer.purchase_id) AND
  (Items.item = BuyEvent.item)
GROUP BY Buyer.purchase_id, Buyer.buyer_id ORDER BY purchase_id)
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
    ARRAY_AGG(DISTINCT (CASE WHEN x_25 = 0 THEN t_5_Buyer.buyer_id ELSE NULL END)) AS logica_value
  FROM
    t_2_Buyer AS t_5_Buyer, UNNEST(ARRAY[0]::numeric[]) as x_25) AS numeric[])) as x_4 ORDER BY buyer_id;
