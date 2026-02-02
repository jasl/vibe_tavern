WITH t_0_Animal AS (SELECT * FROM (
  
    SELECT
      'cat' AS col0 UNION ALL
  
    SELECT
      'dog' AS col0
) AS UNUSED_TABLE_NAME  ),
t_1_Color AS (SELECT * FROM (
  
    SELECT
      'white' AS col0 UNION ALL
  
    SELECT
      'black' AS col0 UNION ALL
  
    SELECT
      'brown' AS col0
) AS UNUSED_TABLE_NAME  ),
t_2_Action AS (SELECT * FROM (
  
    SELECT
      'runs' AS col0 UNION ALL
  
    SELECT
      'jumps' AS col0 UNION ALL
  
    SELECT
      'sleeps' AS col0
) AS UNUSED_TABLE_NAME  )
SELECT
  ((((((((((Color.col0) || (' '))) || (Animal.col0))) || (' '))) || (Action.col0))) || ('.')) AS col0
FROM
  t_0_Animal AS Animal, t_1_Color AS Color, t_2_Action AS Action;
