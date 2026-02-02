SELECT * FROM (
  
    SELECT
      'T' AS col0,
      'a' AS col1,
      'b' AS col2 UNION ALL
  
    SELECT
      'T2' AS col0,
      'A' AS col1,
      'B' AS col2 UNION ALL
  
    SELECT
      'T3' AS col0,
      10 AS col1,
      20 AS col2
) AS UNUSED_TABLE_NAME  ;
