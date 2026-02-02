WITH t_25_Parent AS (SELECT * FROM (
  
    SELECT
      'A' AS col0,
      'B' AS col1 UNION ALL
  
    SELECT
      'B' AS col0,
      'C' AS col1 UNION ALL
  
    SELECT
      'C' AS col0,
      'D' AS col1 UNION ALL
  
    SELECT
      'B' AS col0,
      'E' AS col1
) AS UNUSED_TABLE_NAME  ),
t_24_Closure_MultBodyAggAux_recursive_head_f1_f12 AS (SELECT * FROM (
  
    SELECT
      Parent.col0 AS col0,
      Parent.col1 AS col1
    FROM
      t_25_Parent AS Parent
) AS UNUSED_TABLE_NAME  ),
t_23_Closure_r0_f12 AS (SELECT
  Closure_MultBodyAggAux_recursive_head_f1_f12.col0 AS col0,
  Closure_MultBodyAggAux_recursive_head_f1_f12.col1 AS col1
FROM
  t_24_Closure_MultBodyAggAux_recursive_head_f1_f12 AS Closure_MultBodyAggAux_recursive_head_f1_f12
GROUP BY Closure_MultBodyAggAux_recursive_head_f1_f12.col0, Closure_MultBodyAggAux_recursive_head_f1_f12.col1),
t_21_Closure_MultBodyAggAux_recursive_head_f2_f12 AS (SELECT * FROM (
  
    SELECT
      Closure_r0_f12.col0 AS col0,
      t_22_Closure_r0_f12.col1 AS col1
    FROM
      t_23_Closure_r0_f12 AS Closure_r0_f12, t_23_Closure_r0_f12 AS t_22_Closure_r0_f12
    WHERE
      (t_22_Closure_r0_f12.col0 = Closure_r0_f12.col1) UNION ALL
  
    SELECT
      t_31_Parent.col0 AS col0,
      t_31_Parent.col1 AS col1
    FROM
      t_25_Parent AS t_31_Parent
) AS UNUSED_TABLE_NAME  ),
t_20_Closure_r1_f12 AS (SELECT
  Closure_MultBodyAggAux_recursive_head_f2_f12.col0 AS col0,
  Closure_MultBodyAggAux_recursive_head_f2_f12.col1 AS col1
FROM
  t_21_Closure_MultBodyAggAux_recursive_head_f2_f12 AS Closure_MultBodyAggAux_recursive_head_f2_f12
GROUP BY Closure_MultBodyAggAux_recursive_head_f2_f12.col0, Closure_MultBodyAggAux_recursive_head_f2_f12.col1),
t_18_Closure_MultBodyAggAux_recursive_head_f3_f12 AS (SELECT * FROM (
  
    SELECT
      Closure_r1_f12.col0 AS col0,
      t_19_Closure_r1_f12.col1 AS col1
    FROM
      t_20_Closure_r1_f12 AS Closure_r1_f12, t_20_Closure_r1_f12 AS t_19_Closure_r1_f12
    WHERE
      (t_19_Closure_r1_f12.col0 = Closure_r1_f12.col1) UNION ALL
  
    SELECT
      t_36_Parent.col0 AS col0,
      t_36_Parent.col1 AS col1
    FROM
      t_25_Parent AS t_36_Parent
) AS UNUSED_TABLE_NAME  ),
t_17_Closure_r2_f12 AS (SELECT
  Closure_MultBodyAggAux_recursive_head_f3_f12.col0 AS col0,
  Closure_MultBodyAggAux_recursive_head_f3_f12.col1 AS col1
FROM
  t_18_Closure_MultBodyAggAux_recursive_head_f3_f12 AS Closure_MultBodyAggAux_recursive_head_f3_f12
GROUP BY Closure_MultBodyAggAux_recursive_head_f3_f12.col0, Closure_MultBodyAggAux_recursive_head_f3_f12.col1),
t_15_Closure_MultBodyAggAux_recursive_head_f4_f12 AS (SELECT * FROM (
  
    SELECT
      Closure_r2_f12.col0 AS col0,
      t_16_Closure_r2_f12.col1 AS col1
    FROM
      t_17_Closure_r2_f12 AS Closure_r2_f12, t_17_Closure_r2_f12 AS t_16_Closure_r2_f12
    WHERE
      (t_16_Closure_r2_f12.col0 = Closure_r2_f12.col1) UNION ALL
  
    SELECT
      t_41_Parent.col0 AS col0,
      t_41_Parent.col1 AS col1
    FROM
      t_25_Parent AS t_41_Parent
) AS UNUSED_TABLE_NAME  ),
t_14_Closure_r3_f12 AS (SELECT
  Closure_MultBodyAggAux_recursive_head_f4_f12.col0 AS col0,
  Closure_MultBodyAggAux_recursive_head_f4_f12.col1 AS col1
FROM
  t_15_Closure_MultBodyAggAux_recursive_head_f4_f12 AS Closure_MultBodyAggAux_recursive_head_f4_f12
GROUP BY Closure_MultBodyAggAux_recursive_head_f4_f12.col0, Closure_MultBodyAggAux_recursive_head_f4_f12.col1),
t_12_Closure_MultBodyAggAux_recursive_head_f5_f12 AS (SELECT * FROM (
  
    SELECT
      Closure_r3_f12.col0 AS col0,
      t_13_Closure_r3_f12.col1 AS col1
    FROM
      t_14_Closure_r3_f12 AS Closure_r3_f12, t_14_Closure_r3_f12 AS t_13_Closure_r3_f12
    WHERE
      (t_13_Closure_r3_f12.col0 = Closure_r3_f12.col1) UNION ALL
  
    SELECT
      t_46_Parent.col0 AS col0,
      t_46_Parent.col1 AS col1
    FROM
      t_25_Parent AS t_46_Parent
) AS UNUSED_TABLE_NAME  ),
t_11_Closure_r4_f12 AS (SELECT
  Closure_MultBodyAggAux_recursive_head_f5_f12.col0 AS col0,
  Closure_MultBodyAggAux_recursive_head_f5_f12.col1 AS col1
FROM
  t_12_Closure_MultBodyAggAux_recursive_head_f5_f12 AS Closure_MultBodyAggAux_recursive_head_f5_f12
GROUP BY Closure_MultBodyAggAux_recursive_head_f5_f12.col0, Closure_MultBodyAggAux_recursive_head_f5_f12.col1),
t_9_Closure_MultBodyAggAux_recursive_head_f6_f12 AS (SELECT * FROM (
  
    SELECT
      Closure_r4_f12.col0 AS col0,
      t_10_Closure_r4_f12.col1 AS col1
    FROM
      t_11_Closure_r4_f12 AS Closure_r4_f12, t_11_Closure_r4_f12 AS t_10_Closure_r4_f12
    WHERE
      (t_10_Closure_r4_f12.col0 = Closure_r4_f12.col1) UNION ALL
  
    SELECT
      t_51_Parent.col0 AS col0,
      t_51_Parent.col1 AS col1
    FROM
      t_25_Parent AS t_51_Parent
) AS UNUSED_TABLE_NAME  ),
t_8_Closure_r5_f12 AS (SELECT
  Closure_MultBodyAggAux_recursive_head_f6_f12.col0 AS col0,
  Closure_MultBodyAggAux_recursive_head_f6_f12.col1 AS col1
FROM
  t_9_Closure_MultBodyAggAux_recursive_head_f6_f12 AS Closure_MultBodyAggAux_recursive_head_f6_f12
GROUP BY Closure_MultBodyAggAux_recursive_head_f6_f12.col0, Closure_MultBodyAggAux_recursive_head_f6_f12.col1),
t_6_Closure_MultBodyAggAux_recursive_head_f7_f12 AS (SELECT * FROM (
  
    SELECT
      Closure_r5_f12.col0 AS col0,
      t_7_Closure_r5_f12.col1 AS col1
    FROM
      t_8_Closure_r5_f12 AS Closure_r5_f12, t_8_Closure_r5_f12 AS t_7_Closure_r5_f12
    WHERE
      (t_7_Closure_r5_f12.col0 = Closure_r5_f12.col1) UNION ALL
  
    SELECT
      t_56_Parent.col0 AS col0,
      t_56_Parent.col1 AS col1
    FROM
      t_25_Parent AS t_56_Parent
) AS UNUSED_TABLE_NAME  ),
t_5_Closure_r6_f12 AS (SELECT
  Closure_MultBodyAggAux_recursive_head_f7_f12.col0 AS col0,
  Closure_MultBodyAggAux_recursive_head_f7_f12.col1 AS col1
FROM
  t_6_Closure_MultBodyAggAux_recursive_head_f7_f12 AS Closure_MultBodyAggAux_recursive_head_f7_f12
GROUP BY Closure_MultBodyAggAux_recursive_head_f7_f12.col0, Closure_MultBodyAggAux_recursive_head_f7_f12.col1),
t_3_Closure_MultBodyAggAux_recursive_head_f8_f12 AS (SELECT * FROM (
  
    SELECT
      Closure_r6_f12.col0 AS col0,
      t_4_Closure_r6_f12.col1 AS col1
    FROM
      t_5_Closure_r6_f12 AS Closure_r6_f12, t_5_Closure_r6_f12 AS t_4_Closure_r6_f12
    WHERE
      (t_4_Closure_r6_f12.col0 = Closure_r6_f12.col1) UNION ALL
  
    SELECT
      t_61_Parent.col0 AS col0,
      t_61_Parent.col1 AS col1
    FROM
      t_25_Parent AS t_61_Parent
) AS UNUSED_TABLE_NAME  ),
t_2_Closure_r7_f12 AS (SELECT
  Closure_MultBodyAggAux_recursive_head_f8_f12.col0 AS col0,
  Closure_MultBodyAggAux_recursive_head_f8_f12.col1 AS col1
FROM
  t_3_Closure_MultBodyAggAux_recursive_head_f8_f12 AS Closure_MultBodyAggAux_recursive_head_f8_f12
GROUP BY Closure_MultBodyAggAux_recursive_head_f8_f12.col0, Closure_MultBodyAggAux_recursive_head_f8_f12.col1),
t_0_Closure_MultBodyAggAux_recursive_head_f9_f12 AS (SELECT * FROM (
  
    SELECT
      Closure_r7_f12.col0 AS col0,
      t_1_Closure_r7_f12.col1 AS col1
    FROM
      t_2_Closure_r7_f12 AS Closure_r7_f12, t_2_Closure_r7_f12 AS t_1_Closure_r7_f12
    WHERE
      (t_1_Closure_r7_f12.col0 = Closure_r7_f12.col1) UNION ALL
  
    SELECT
      t_66_Parent.col0 AS col0,
      t_66_Parent.col1 AS col1
    FROM
      t_25_Parent AS t_66_Parent
) AS UNUSED_TABLE_NAME  )
SELECT
  Closure_MultBodyAggAux_recursive_head_f9_f12.col0 AS col0,
  Closure_MultBodyAggAux_recursive_head_f9_f12.col1 AS col1
FROM
  t_0_Closure_MultBodyAggAux_recursive_head_f9_f12 AS Closure_MultBodyAggAux_recursive_head_f9_f12
GROUP BY Closure_MultBodyAggAux_recursive_head_f9_f12.col0, Closure_MultBodyAggAux_recursive_head_f9_f12.col1;
