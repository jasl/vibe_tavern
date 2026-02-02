WITH t_0_T AS (SELECT * FROM (
  
    SELECT
      1 AS col0 UNION ALL
  
    SELECT
      2 AS col0 UNION ALL
  
    SELECT
      3 AS col0 UNION ALL
  
    SELECT
      4 AS col0
) AS UNUSED_TABLE_NAME  ),
t_3_R AS (SELECT
  t_4_T.col0 AS col0,
  CASE WHEN ((t_4_T.col0 = 2) OR (t_4_T.col0 = 3)) THEN JSON_ARRAY(t_4_T.col0) ELSE JSON_ARRAY() END AS col1
FROM
  t_0_T AS t_4_T),
t_1_P2 AS (SELECT
  t_2_T.col0 AS col0,
  JSON_GROUP_ARRAY(x_15.value) AS col1
FROM
  t_0_T AS t_2_T, t_3_R AS R, JSON_EACH(JSON_ARRAY(1, 2, 3, 4)) as x_15
WHERE
  ((SELECT
    MIN(MagicalEntangle(1, x_23.value)) AS logica_value
  FROM
    JSON_EACH(R.col1) as x_22, JSON_EACH(JSON_ARRAY(0)) as x_23
  WHERE
    (x_15.value = x_22.value)) IS NULL) AND
  (R.col0 = t_2_T.col0)
GROUP BY t_2_T.col0),
t_7_P AS (SELECT * FROM (
  
    SELECT
      1 AS col0 UNION ALL
  
    SELECT
      2 AS col0
) AS UNUSED_TABLE_NAME  )
SELECT * FROM (
  
    SELECT
      '1' AS col0,
      T.col0 AS col1,
      (SELECT
      SUM(MagicalEntangle(T.col0, x_8.value)) AS logica_value
    FROM
      JSON_EACH(JSON_ARRAY(0)) as x_8) AS col2
    FROM
      t_0_T AS T UNION ALL
  
    SELECT
      '2' AS col0,
      P2.col0 AS col1,
      P2.col1 AS col2
    FROM
      t_1_P2 AS P2 UNION ALL
  
    SELECT
      '3' AS col0,
      t_5_T.col0 AS col1,
      NOT ((SELECT
      MIN(MagicalEntangle(1, x_38.value)) AS logica_value
    FROM
      t_7_P AS P, JSON_EACH(JSON_ARRAY(0)) as x_38
    WHERE
      (P.col0 = t_5_T.col0)) IS NULL) AS col2
    FROM
      t_0_T AS t_5_T
) AS UNUSED_TABLE_NAME  ;
