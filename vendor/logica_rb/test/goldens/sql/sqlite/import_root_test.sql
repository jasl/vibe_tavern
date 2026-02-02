WITH t_1_Usa_ProductUSA AS (SELECT * FROM (
  
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
t_0_Taxation_ProductTax AS (SELECT
  Usa_ProductUSA.col0 AS col0,
  ((Usa_ProductUSA.price) * (0.1)) AS tax
FROM
  t_1_Usa_ProductUSA AS Usa_ProductUSA)
SELECT
  Taxation_ProductTax.*
FROM
  t_0_Taxation_ProductTax AS Taxation_ProductTax;
