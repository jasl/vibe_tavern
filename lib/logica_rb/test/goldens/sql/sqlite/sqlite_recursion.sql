WITH t_21_Edge AS (SELECT * FROM (
  
    SELECT
      1 AS col0,
      2 AS col1 UNION ALL
  
    SELECT
      2 AS col0,
      3 AS col1 UNION ALL
  
    SELECT
      3 AS col0,
      4 AS col1 UNION ALL
  
    SELECT
      4 AS col0,
      5 AS col1 UNION ALL
  
    SELECT
      6 AS col0,
      7 AS col1 UNION ALL
  
    SELECT
      7 AS col0,
      8 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      10 AS col1 UNION ALL
  
    SELECT
      10 AS col0,
      11 AS col1 UNION ALL
  
    SELECT
      9 AS col0,
      11 AS col1
) AS UNUSED_TABLE_NAME  ),
t_17_Distance_MultBodyAggAux_recursive_head_f1 AS (SELECT * FROM (
  
    SELECT
      Edge.col0 AS col0,
      Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_21_Edge AS Edge
) AS UNUSED_TABLE_NAME  ),
t_16_Distance_r0 AS (SELECT
  Distance_MultBodyAggAux_recursive_head_f1.col0 AS col0,
  Distance_MultBodyAggAux_recursive_head_f1.col1 AS col1,
  MIN(Distance_MultBodyAggAux_recursive_head_f1.logica_value) AS logica_value
FROM
  t_17_Distance_MultBodyAggAux_recursive_head_f1 AS Distance_MultBodyAggAux_recursive_head_f1
GROUP BY Distance_MultBodyAggAux_recursive_head_f1.col0, Distance_MultBodyAggAux_recursive_head_f1.col1 ORDER BY col0, col1),
t_15_Distance_MultBodyAggAux_recursive_head_f2 AS (SELECT * FROM (
  
    SELECT
      Distance_r0.col0 AS col0,
      Distance_r0.col0 AS col1,
      0 AS logica_value
    FROM
      t_16_Distance_r0 AS Distance_r0 UNION ALL
  
    SELECT
      t_22_Distance_r0.col0 AS col0,
      t_23_Distance_r0.col1 AS col1,
      ((t_22_Distance_r0.logica_value) + (t_23_Distance_r0.logica_value)) AS logica_value
    FROM
      t_16_Distance_r0 AS t_22_Distance_r0, t_16_Distance_r0 AS t_23_Distance_r0
    WHERE
      (t_23_Distance_r0.col0 = t_22_Distance_r0.col1) UNION ALL
  
    SELECT
      t_30_Distance_r0.col1 AS col0,
      t_30_Distance_r0.col0 AS col1,
      t_30_Distance_r0.logica_value AS logica_value
    FROM
      t_16_Distance_r0 AS t_30_Distance_r0 UNION ALL
  
    SELECT
      t_31_Edge.col0 AS col0,
      t_31_Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_21_Edge AS t_31_Edge
) AS UNUSED_TABLE_NAME  ),
t_14_Distance_r1 AS (SELECT
  Distance_MultBodyAggAux_recursive_head_f2.col0 AS col0,
  Distance_MultBodyAggAux_recursive_head_f2.col1 AS col1,
  MIN(Distance_MultBodyAggAux_recursive_head_f2.logica_value) AS logica_value
FROM
  t_15_Distance_MultBodyAggAux_recursive_head_f2 AS Distance_MultBodyAggAux_recursive_head_f2
GROUP BY Distance_MultBodyAggAux_recursive_head_f2.col0, Distance_MultBodyAggAux_recursive_head_f2.col1 ORDER BY col0, col1),
t_13_Distance_MultBodyAggAux_recursive_head_f3 AS (SELECT * FROM (
  
    SELECT
      Distance_r1.col0 AS col0,
      Distance_r1.col0 AS col1,
      0 AS logica_value
    FROM
      t_14_Distance_r1 AS Distance_r1 UNION ALL
  
    SELECT
      t_32_Distance_r1.col0 AS col0,
      t_33_Distance_r1.col1 AS col1,
      ((t_32_Distance_r1.logica_value) + (t_33_Distance_r1.logica_value)) AS logica_value
    FROM
      t_14_Distance_r1 AS t_32_Distance_r1, t_14_Distance_r1 AS t_33_Distance_r1
    WHERE
      (t_33_Distance_r1.col0 = t_32_Distance_r1.col1) UNION ALL
  
    SELECT
      t_40_Distance_r1.col1 AS col0,
      t_40_Distance_r1.col0 AS col1,
      t_40_Distance_r1.logica_value AS logica_value
    FROM
      t_14_Distance_r1 AS t_40_Distance_r1 UNION ALL
  
    SELECT
      t_41_Edge.col0 AS col0,
      t_41_Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_21_Edge AS t_41_Edge
) AS UNUSED_TABLE_NAME  ),
t_12_Distance_r2 AS (SELECT
  Distance_MultBodyAggAux_recursive_head_f3.col0 AS col0,
  Distance_MultBodyAggAux_recursive_head_f3.col1 AS col1,
  MIN(Distance_MultBodyAggAux_recursive_head_f3.logica_value) AS logica_value
FROM
  t_13_Distance_MultBodyAggAux_recursive_head_f3 AS Distance_MultBodyAggAux_recursive_head_f3
GROUP BY Distance_MultBodyAggAux_recursive_head_f3.col0, Distance_MultBodyAggAux_recursive_head_f3.col1 ORDER BY col0, col1),
t_11_Distance_MultBodyAggAux_recursive_head_f4 AS (SELECT * FROM (
  
    SELECT
      Distance_r2.col0 AS col0,
      Distance_r2.col0 AS col1,
      0 AS logica_value
    FROM
      t_12_Distance_r2 AS Distance_r2 UNION ALL
  
    SELECT
      t_42_Distance_r2.col0 AS col0,
      t_43_Distance_r2.col1 AS col1,
      ((t_42_Distance_r2.logica_value) + (t_43_Distance_r2.logica_value)) AS logica_value
    FROM
      t_12_Distance_r2 AS t_42_Distance_r2, t_12_Distance_r2 AS t_43_Distance_r2
    WHERE
      (t_43_Distance_r2.col0 = t_42_Distance_r2.col1) UNION ALL
  
    SELECT
      t_50_Distance_r2.col1 AS col0,
      t_50_Distance_r2.col0 AS col1,
      t_50_Distance_r2.logica_value AS logica_value
    FROM
      t_12_Distance_r2 AS t_50_Distance_r2 UNION ALL
  
    SELECT
      t_51_Edge.col0 AS col0,
      t_51_Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_21_Edge AS t_51_Edge
) AS UNUSED_TABLE_NAME  ),
t_10_Distance_r3 AS (SELECT
  Distance_MultBodyAggAux_recursive_head_f4.col0 AS col0,
  Distance_MultBodyAggAux_recursive_head_f4.col1 AS col1,
  MIN(Distance_MultBodyAggAux_recursive_head_f4.logica_value) AS logica_value
FROM
  t_11_Distance_MultBodyAggAux_recursive_head_f4 AS Distance_MultBodyAggAux_recursive_head_f4
GROUP BY Distance_MultBodyAggAux_recursive_head_f4.col0, Distance_MultBodyAggAux_recursive_head_f4.col1 ORDER BY col0, col1),
t_9_Distance_MultBodyAggAux_recursive_head_f5 AS (SELECT * FROM (
  
    SELECT
      Distance_r3.col0 AS col0,
      Distance_r3.col0 AS col1,
      0 AS logica_value
    FROM
      t_10_Distance_r3 AS Distance_r3 UNION ALL
  
    SELECT
      t_52_Distance_r3.col0 AS col0,
      t_53_Distance_r3.col1 AS col1,
      ((t_52_Distance_r3.logica_value) + (t_53_Distance_r3.logica_value)) AS logica_value
    FROM
      t_10_Distance_r3 AS t_52_Distance_r3, t_10_Distance_r3 AS t_53_Distance_r3
    WHERE
      (t_53_Distance_r3.col0 = t_52_Distance_r3.col1) UNION ALL
  
    SELECT
      t_60_Distance_r3.col1 AS col0,
      t_60_Distance_r3.col0 AS col1,
      t_60_Distance_r3.logica_value AS logica_value
    FROM
      t_10_Distance_r3 AS t_60_Distance_r3 UNION ALL
  
    SELECT
      t_61_Edge.col0 AS col0,
      t_61_Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_21_Edge AS t_61_Edge
) AS UNUSED_TABLE_NAME  ),
t_8_Distance_r4 AS (SELECT
  Distance_MultBodyAggAux_recursive_head_f5.col0 AS col0,
  Distance_MultBodyAggAux_recursive_head_f5.col1 AS col1,
  MIN(Distance_MultBodyAggAux_recursive_head_f5.logica_value) AS logica_value
FROM
  t_9_Distance_MultBodyAggAux_recursive_head_f5 AS Distance_MultBodyAggAux_recursive_head_f5
GROUP BY Distance_MultBodyAggAux_recursive_head_f5.col0, Distance_MultBodyAggAux_recursive_head_f5.col1 ORDER BY col0, col1),
t_7_Distance_MultBodyAggAux_recursive_head_f6 AS (SELECT * FROM (
  
    SELECT
      Distance_r4.col0 AS col0,
      Distance_r4.col0 AS col1,
      0 AS logica_value
    FROM
      t_8_Distance_r4 AS Distance_r4 UNION ALL
  
    SELECT
      t_62_Distance_r4.col0 AS col0,
      t_63_Distance_r4.col1 AS col1,
      ((t_62_Distance_r4.logica_value) + (t_63_Distance_r4.logica_value)) AS logica_value
    FROM
      t_8_Distance_r4 AS t_62_Distance_r4, t_8_Distance_r4 AS t_63_Distance_r4
    WHERE
      (t_63_Distance_r4.col0 = t_62_Distance_r4.col1) UNION ALL
  
    SELECT
      t_70_Distance_r4.col1 AS col0,
      t_70_Distance_r4.col0 AS col1,
      t_70_Distance_r4.logica_value AS logica_value
    FROM
      t_8_Distance_r4 AS t_70_Distance_r4 UNION ALL
  
    SELECT
      t_71_Edge.col0 AS col0,
      t_71_Edge.col1 AS col1,
      1 AS logica_value
    FROM
      t_21_Edge AS t_71_Edge
) AS UNUSED_TABLE_NAME  ),
t_6_Distance AS (SELECT
  Distance_MultBodyAggAux_recursive_head_f6.col0 AS col0,
  Distance_MultBodyAggAux_recursive_head_f6.col1 AS col1,
  MIN(Distance_MultBodyAggAux_recursive_head_f6.logica_value) AS logica_value
FROM
  t_7_Distance_MultBodyAggAux_recursive_head_f6 AS Distance_MultBodyAggAux_recursive_head_f6
GROUP BY Distance_MultBodyAggAux_recursive_head_f6.col0, Distance_MultBodyAggAux_recursive_head_f6.col1 ORDER BY col0, col1),
t_4_ComponentOf AS (SELECT
  t_5_Distance.col0 AS col0,
  MIN(t_5_Distance.col1) AS logica_value
FROM
  t_6_Distance AS t_5_Distance
GROUP BY t_5_Distance.col0 ORDER BY col0)
SELECT
  t_0_ComponentOf.col0 AS vertex,
  t_3_ComponentOf.logica_value AS component,
  MAX(Distance.logica_value) AS diameter
FROM
  t_4_ComponentOf AS ComponentOf, t_4_ComponentOf AS t_0_ComponentOf, t_4_ComponentOf AS t_1_ComponentOf, t_4_ComponentOf AS t_2_ComponentOf, t_4_ComponentOf AS t_3_ComponentOf, t_6_Distance AS Distance
WHERE
  (ComponentOf.logica_value = t_0_ComponentOf.logica_value) AND
  (t_1_ComponentOf.logica_value = t_2_ComponentOf.logica_value) AND
  (t_2_ComponentOf.col0 = t_0_ComponentOf.col0) AND
  (t_3_ComponentOf.col0 = t_0_ComponentOf.col0) AND
  (Distance.col0 = ComponentOf.col0) AND
  (Distance.col1 = t_1_ComponentOf.col0)
GROUP BY t_0_ComponentOf.col0, t_3_ComponentOf.logica_value ORDER BY vertex;
