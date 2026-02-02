SELECT * FROM (
  
    SELECT
      SQRT(2) AS col0 UNION ALL
  
    SELECT
      (POW(2, 3)) AS col0 UNION ALL
  
    SELECT
      EXP(1) AS col0 UNION ALL
  
    SELECT
      LOG((POW(2.7182818284, 5))) AS col0 UNION ALL
  
    SELECT
      SIN(((3.141592) / (3))) AS col0 UNION ALL
  
    SELECT
      COS(((3.141592) / (3))) AS col0 UNION ALL
  
    SELECT
      ACOS(-1) AS col0 UNION ALL
  
    SELECT
      ASIN(1) AS col0 UNION ALL
  
    SELECT
      SPLIT('a,b,cd,ef', ',') AS col0 UNION ALL
  
    SELECT
      JOIN_STRINGS(JSON_ARRAY('abc', 'de', 'fg'), ',') AS col0
) AS UNUSED_TABLE_NAME  ;
