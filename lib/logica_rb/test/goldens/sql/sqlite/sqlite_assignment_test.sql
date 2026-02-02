WITH t_3_CustomerPurchase AS (SELECT * FROM (
  
    SELECT
      'John' AS customer_name,
      'apple' AS item_name,
      2 AS quantity UNION ALL
  
    SELECT
      'John' AS customer_name,
      'banana' AS item_name,
      1 AS quantity UNION ALL
  
    SELECT
      'John' AS customer_name,
      'orange' AS item_name,
      3 AS quantity UNION ALL
  
    SELECT
      'John' AS customer_name,
      'orange' AS item_name,
      3 AS quantity UNION ALL
  
    SELECT
      'Jane' AS customer_name,
      'pear' AS item_name,
      1 AS quantity UNION ALL
  
    SELECT
      'Jane' AS customer_name,
      'banana' AS item_name,
      2 AS quantity UNION ALL
  
    SELECT
      'Jane' AS customer_name,
      'apple' AS item_name,
      2 AS quantity
) AS UNUSED_TABLE_NAME  ),
t_4_PercentageDiscout AS (SELECT * FROM (
  
    SELECT
      'apple' AS item_name,
      10 AS percentage UNION ALL
  
    SELECT
      'orange' AS item_name,
      20 AS percentage
) AS UNUSED_TABLE_NAME  ),
t_5_StoreItem AS (SELECT * FROM (
  
    SELECT
      'apple' AS name,
      2.0 AS price UNION ALL
  
    SELECT
      'banana' AS name,
      1.0 AS price UNION ALL
  
    SELECT
      'orange' AS name,
      1.5 AS price UNION ALL
  
    SELECT
      'pear' AS name,
      3.0 AS price
) AS UNUSED_TABLE_NAME  )
SELECT
  CustomerPurchase.customer_name AS customer_name,
  SUM(((((StoreItem.price) * (((t_0_PercentageDiscout.percentage) / (100.0))))) * (CustomerPurchase.quantity))) AS total_savings,
  MAX(((t_0_PercentageDiscout.percentage) / (100.0))) AS max_fraction
FROM
  t_3_CustomerPurchase AS CustomerPurchase, t_4_PercentageDiscout AS PercentageDiscout, t_5_StoreItem AS StoreItem, t_4_PercentageDiscout AS t_0_PercentageDiscout
WHERE
  (PercentageDiscout.item_name = CustomerPurchase.item_name) AND
  (StoreItem.name = CustomerPurchase.item_name) AND
  (t_0_PercentageDiscout.item_name = CustomerPurchase.item_name)
GROUP BY CustomerPurchase.customer_name ORDER BY customer_name;
