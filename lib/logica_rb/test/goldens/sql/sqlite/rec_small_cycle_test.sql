WITH t_17_C_recursive_head_f1 AS (SELECT * FROM (
  
    SELECT
      0 AS col0
) AS UNUSED_TABLE_NAME  ),
t_16_A_r0 AS (SELECT
  C_recursive_head_f1.col0 AS col0
FROM
  t_17_C_recursive_head_f1 AS C_recursive_head_f1
GROUP BY C_recursive_head_f1.col0),
t_15_C_recursive_head_f2 AS (SELECT * FROM (
  
    SELECT
      A_r0.col0 AS col0
    FROM
      t_16_A_r0 AS A_r0 UNION ALL
  
    SELECT
      0 AS col0
) AS UNUSED_TABLE_NAME  ),
t_14_A_r1 AS (SELECT
  C_recursive_head_f2.col0 AS col0
FROM
  t_15_C_recursive_head_f2 AS C_recursive_head_f2
GROUP BY C_recursive_head_f2.col0),
t_13_C_recursive_head_f3 AS (SELECT * FROM (
  
    SELECT
      A_r1.col0 AS col0
    FROM
      t_14_A_r1 AS A_r1 UNION ALL
  
    SELECT
      0 AS col0
) AS UNUSED_TABLE_NAME  ),
t_12_A_r2 AS (SELECT
  C_recursive_head_f3.col0 AS col0
FROM
  t_13_C_recursive_head_f3 AS C_recursive_head_f3
GROUP BY C_recursive_head_f3.col0),
t_11_C_recursive_head_f4 AS (SELECT * FROM (
  
    SELECT
      A_r2.col0 AS col0
    FROM
      t_12_A_r2 AS A_r2 UNION ALL
  
    SELECT
      0 AS col0
) AS UNUSED_TABLE_NAME  ),
t_10_A_r3 AS (SELECT
  C_recursive_head_f4.col0 AS col0
FROM
  t_11_C_recursive_head_f4 AS C_recursive_head_f4
GROUP BY C_recursive_head_f4.col0),
t_9_C_recursive_head_f5 AS (SELECT * FROM (
  
    SELECT
      A_r3.col0 AS col0
    FROM
      t_10_A_r3 AS A_r3 UNION ALL
  
    SELECT
      0 AS col0
) AS UNUSED_TABLE_NAME  ),
t_8_A_r4 AS (SELECT
  C_recursive_head_f5.col0 AS col0
FROM
  t_9_C_recursive_head_f5 AS C_recursive_head_f5
GROUP BY C_recursive_head_f5.col0),
t_7_C_recursive_head_f6 AS (SELECT * FROM (
  
    SELECT
      A_r4.col0 AS col0
    FROM
      t_8_A_r4 AS A_r4 UNION ALL
  
    SELECT
      0 AS col0
) AS UNUSED_TABLE_NAME  ),
t_6_A_r5 AS (SELECT
  C_recursive_head_f6.col0 AS col0
FROM
  t_7_C_recursive_head_f6 AS C_recursive_head_f6
GROUP BY C_recursive_head_f6.col0),
t_5_C_recursive_head_f7 AS (SELECT * FROM (
  
    SELECT
      A_r5.col0 AS col0
    FROM
      t_6_A_r5 AS A_r5 UNION ALL
  
    SELECT
      0 AS col0
) AS UNUSED_TABLE_NAME  ),
t_4_A_r6 AS (SELECT
  C_recursive_head_f7.col0 AS col0
FROM
  t_5_C_recursive_head_f7 AS C_recursive_head_f7
GROUP BY C_recursive_head_f7.col0),
t_3_C_recursive_head_f8 AS (SELECT * FROM (
  
    SELECT
      A_r6.col0 AS col0
    FROM
      t_4_A_r6 AS A_r6 UNION ALL
  
    SELECT
      0 AS col0
) AS UNUSED_TABLE_NAME  ),
t_2_A_r7 AS (SELECT
  C_recursive_head_f8.col0 AS col0
FROM
  t_3_C_recursive_head_f8 AS C_recursive_head_f8
GROUP BY C_recursive_head_f8.col0),
t_1_C_recursive_head_f9 AS (SELECT * FROM (
  
    SELECT
      A_r7.col0 AS col0
    FROM
      t_2_A_r7 AS A_r7 UNION ALL
  
    SELECT
      0 AS col0
) AS UNUSED_TABLE_NAME  ),
t_0_A AS (SELECT
  C_recursive_head_f9.col0 AS col0
FROM
  t_1_C_recursive_head_f9 AS C_recursive_head_f9
GROUP BY C_recursive_head_f9.col0)
SELECT
  A.col0 AS col0
FROM
  t_0_A AS A;
