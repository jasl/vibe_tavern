WITH t_17_NumSlow_MultBodyAggAux_recursive_head_f1 AS (SELECT * FROM (
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_16_NumSlow_r0 AS (SELECT
  NumSlow_MultBodyAggAux_recursive_head_f1.col0 AS col0
FROM
  t_17_NumSlow_MultBodyAggAux_recursive_head_f1 AS NumSlow_MultBodyAggAux_recursive_head_f1
GROUP BY NumSlow_MultBodyAggAux_recursive_head_f1.col0),
t_15_NumSlow_MultBodyAggAux_recursive_head_f2 AS (SELECT * FROM (
  
    SELECT
      ((NumSlow_r0.col0) + (1)) AS col0
    FROM
      t_16_NumSlow_r0 AS NumSlow_r0 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_14_NumSlow_r1 AS (SELECT
  NumSlow_MultBodyAggAux_recursive_head_f2.col0 AS col0
FROM
  t_15_NumSlow_MultBodyAggAux_recursive_head_f2 AS NumSlow_MultBodyAggAux_recursive_head_f2
GROUP BY NumSlow_MultBodyAggAux_recursive_head_f2.col0),
t_13_NumSlow_MultBodyAggAux_recursive_head_f3 AS (SELECT * FROM (
  
    SELECT
      ((NumSlow_r1.col0) + (1)) AS col0
    FROM
      t_14_NumSlow_r1 AS NumSlow_r1 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_12_NumSlow_r2 AS (SELECT
  NumSlow_MultBodyAggAux_recursive_head_f3.col0 AS col0
FROM
  t_13_NumSlow_MultBodyAggAux_recursive_head_f3 AS NumSlow_MultBodyAggAux_recursive_head_f3
GROUP BY NumSlow_MultBodyAggAux_recursive_head_f3.col0),
t_11_NumSlow_MultBodyAggAux_recursive_head_f4 AS (SELECT * FROM (
  
    SELECT
      ((NumSlow_r2.col0) + (1)) AS col0
    FROM
      t_12_NumSlow_r2 AS NumSlow_r2 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_10_NumSlow_r3 AS (SELECT
  NumSlow_MultBodyAggAux_recursive_head_f4.col0 AS col0
FROM
  t_11_NumSlow_MultBodyAggAux_recursive_head_f4 AS NumSlow_MultBodyAggAux_recursive_head_f4
GROUP BY NumSlow_MultBodyAggAux_recursive_head_f4.col0),
t_9_NumSlow_MultBodyAggAux_recursive_head_f5 AS (SELECT * FROM (
  
    SELECT
      ((NumSlow_r3.col0) + (1)) AS col0
    FROM
      t_10_NumSlow_r3 AS NumSlow_r3 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_8_NumSlow_r4 AS (SELECT
  NumSlow_MultBodyAggAux_recursive_head_f5.col0 AS col0
FROM
  t_9_NumSlow_MultBodyAggAux_recursive_head_f5 AS NumSlow_MultBodyAggAux_recursive_head_f5
GROUP BY NumSlow_MultBodyAggAux_recursive_head_f5.col0),
t_7_NumSlow_MultBodyAggAux_recursive_head_f6 AS (SELECT * FROM (
  
    SELECT
      ((NumSlow_r4.col0) + (1)) AS col0
    FROM
      t_8_NumSlow_r4 AS NumSlow_r4 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_6_NumSlow_r5 AS (SELECT
  NumSlow_MultBodyAggAux_recursive_head_f6.col0 AS col0
FROM
  t_7_NumSlow_MultBodyAggAux_recursive_head_f6 AS NumSlow_MultBodyAggAux_recursive_head_f6
GROUP BY NumSlow_MultBodyAggAux_recursive_head_f6.col0),
t_5_NumSlow_MultBodyAggAux_recursive_head_f7 AS (SELECT * FROM (
  
    SELECT
      ((NumSlow_r5.col0) + (1)) AS col0
    FROM
      t_6_NumSlow_r5 AS NumSlow_r5 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_4_NumSlow_r6 AS (SELECT
  NumSlow_MultBodyAggAux_recursive_head_f7.col0 AS col0
FROM
  t_5_NumSlow_MultBodyAggAux_recursive_head_f7 AS NumSlow_MultBodyAggAux_recursive_head_f7
GROUP BY NumSlow_MultBodyAggAux_recursive_head_f7.col0),
t_3_NumSlow_MultBodyAggAux_recursive_head_f8 AS (SELECT * FROM (
  
    SELECT
      ((NumSlow_r6.col0) + (1)) AS col0
    FROM
      t_4_NumSlow_r6 AS NumSlow_r6 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_2_NumSlow_r7 AS (SELECT
  NumSlow_MultBodyAggAux_recursive_head_f8.col0 AS col0
FROM
  t_3_NumSlow_MultBodyAggAux_recursive_head_f8 AS NumSlow_MultBodyAggAux_recursive_head_f8
GROUP BY NumSlow_MultBodyAggAux_recursive_head_f8.col0),
t_1_NumSlow_MultBodyAggAux_recursive_head_f9 AS (SELECT * FROM (
  
    SELECT
      ((NumSlow_r7.col0) + (1)) AS col0
    FROM
      t_2_NumSlow_r7 AS NumSlow_r7 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_0_NumSlow AS (SELECT
  NumSlow_MultBodyAggAux_recursive_head_f9.col0 AS col0
FROM
  t_1_NumSlow_MultBodyAggAux_recursive_head_f9 AS NumSlow_MultBodyAggAux_recursive_head_f9
GROUP BY NumSlow_MultBodyAggAux_recursive_head_f9.col0),
t_54_Num_MultBodyAggAux_recursive_head_f10 AS (SELECT * FROM (
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_53_Num_r0 AS (SELECT
  Num_MultBodyAggAux_recursive_head_f10.col0 AS col0
FROM
  t_54_Num_MultBodyAggAux_recursive_head_f10 AS Num_MultBodyAggAux_recursive_head_f10
GROUP BY Num_MultBodyAggAux_recursive_head_f10.col0),
t_52_Num_MultBodyAggAux_recursive_head_f11 AS (SELECT * FROM (
  
    SELECT
      ((((2) * (Num_r0.col0))) + (0)) AS col0
    FROM
      t_53_Num_r0 AS Num_r0 UNION ALL
  
    SELECT
      ((((2) * (t_57_Num_r0.col0))) + (1)) AS col0
    FROM
      t_53_Num_r0 AS t_57_Num_r0 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_51_Num_r1 AS (SELECT
  Num_MultBodyAggAux_recursive_head_f11.col0 AS col0
FROM
  t_52_Num_MultBodyAggAux_recursive_head_f11 AS Num_MultBodyAggAux_recursive_head_f11
GROUP BY Num_MultBodyAggAux_recursive_head_f11.col0),
t_50_Num_MultBodyAggAux_recursive_head_f12 AS (SELECT * FROM (
  
    SELECT
      ((((2) * (Num_r1.col0))) + (0)) AS col0
    FROM
      t_51_Num_r1 AS Num_r1 UNION ALL
  
    SELECT
      ((((2) * (t_61_Num_r1.col0))) + (1)) AS col0
    FROM
      t_51_Num_r1 AS t_61_Num_r1 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_49_Num_r2 AS (SELECT
  Num_MultBodyAggAux_recursive_head_f12.col0 AS col0
FROM
  t_50_Num_MultBodyAggAux_recursive_head_f12 AS Num_MultBodyAggAux_recursive_head_f12
GROUP BY Num_MultBodyAggAux_recursive_head_f12.col0),
t_48_Num_MultBodyAggAux_recursive_head_f13 AS (SELECT * FROM (
  
    SELECT
      ((((2) * (Num_r2.col0))) + (0)) AS col0
    FROM
      t_49_Num_r2 AS Num_r2 UNION ALL
  
    SELECT
      ((((2) * (t_65_Num_r2.col0))) + (1)) AS col0
    FROM
      t_49_Num_r2 AS t_65_Num_r2 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_47_Num_r3 AS (SELECT
  Num_MultBodyAggAux_recursive_head_f13.col0 AS col0
FROM
  t_48_Num_MultBodyAggAux_recursive_head_f13 AS Num_MultBodyAggAux_recursive_head_f13
GROUP BY Num_MultBodyAggAux_recursive_head_f13.col0),
t_46_Num_MultBodyAggAux_recursive_head_f14 AS (SELECT * FROM (
  
    SELECT
      ((((2) * (Num_r3.col0))) + (0)) AS col0
    FROM
      t_47_Num_r3 AS Num_r3 UNION ALL
  
    SELECT
      ((((2) * (t_69_Num_r3.col0))) + (1)) AS col0
    FROM
      t_47_Num_r3 AS t_69_Num_r3 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_45_Num_r4 AS (SELECT
  Num_MultBodyAggAux_recursive_head_f14.col0 AS col0
FROM
  t_46_Num_MultBodyAggAux_recursive_head_f14 AS Num_MultBodyAggAux_recursive_head_f14
GROUP BY Num_MultBodyAggAux_recursive_head_f14.col0),
t_44_Num_MultBodyAggAux_recursive_head_f15 AS (SELECT * FROM (
  
    SELECT
      ((((2) * (Num_r4.col0))) + (0)) AS col0
    FROM
      t_45_Num_r4 AS Num_r4 UNION ALL
  
    SELECT
      ((((2) * (t_73_Num_r4.col0))) + (1)) AS col0
    FROM
      t_45_Num_r4 AS t_73_Num_r4 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_43_Num_r5 AS (SELECT
  Num_MultBodyAggAux_recursive_head_f15.col0 AS col0
FROM
  t_44_Num_MultBodyAggAux_recursive_head_f15 AS Num_MultBodyAggAux_recursive_head_f15
GROUP BY Num_MultBodyAggAux_recursive_head_f15.col0),
t_42_Num_MultBodyAggAux_recursive_head_f16 AS (SELECT * FROM (
  
    SELECT
      ((((2) * (Num_r5.col0))) + (0)) AS col0
    FROM
      t_43_Num_r5 AS Num_r5 UNION ALL
  
    SELECT
      ((((2) * (t_77_Num_r5.col0))) + (1)) AS col0
    FROM
      t_43_Num_r5 AS t_77_Num_r5 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_41_Num_r6 AS (SELECT
  Num_MultBodyAggAux_recursive_head_f16.col0 AS col0
FROM
  t_42_Num_MultBodyAggAux_recursive_head_f16 AS Num_MultBodyAggAux_recursive_head_f16
GROUP BY Num_MultBodyAggAux_recursive_head_f16.col0),
t_40_Num_MultBodyAggAux_recursive_head_f17 AS (SELECT * FROM (
  
    SELECT
      ((((2) * (Num_r6.col0))) + (0)) AS col0
    FROM
      t_41_Num_r6 AS Num_r6 UNION ALL
  
    SELECT
      ((((2) * (t_81_Num_r6.col0))) + (1)) AS col0
    FROM
      t_41_Num_r6 AS t_81_Num_r6 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_39_Num_r7 AS (SELECT
  Num_MultBodyAggAux_recursive_head_f17.col0 AS col0
FROM
  t_40_Num_MultBodyAggAux_recursive_head_f17 AS Num_MultBodyAggAux_recursive_head_f17
GROUP BY Num_MultBodyAggAux_recursive_head_f17.col0),
t_38_Num_MultBodyAggAux_recursive_head_f18 AS (SELECT * FROM (
  
    SELECT
      ((((2) * (Num_r7.col0))) + (0)) AS col0
    FROM
      t_39_Num_r7 AS Num_r7 UNION ALL
  
    SELECT
      ((((2) * (t_85_Num_r7.col0))) + (1)) AS col0
    FROM
      t_39_Num_r7 AS t_85_Num_r7 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_37_Num AS (SELECT
  Num_MultBodyAggAux_recursive_head_f18.col0 AS col0
FROM
  t_38_Num_MultBodyAggAux_recursive_head_f18 AS Num_MultBodyAggAux_recursive_head_f18
GROUP BY Num_MultBodyAggAux_recursive_head_f18.col0)
SELECT
  (SELECT
  MAX(MagicalEntangle(NumSlow.col0, x_8.value)) AS logica_value
FROM
  t_0_NumSlow AS NumSlow, JSON_EACH(JSON_ARRAY(0)) as x_8) AS num_slow_max,
  (SELECT
  SUM(MagicalEntangle(1, x_37.value)) AS logica_value
FROM
  t_0_NumSlow AS t_18_NumSlow, JSON_EACH(JSON_ARRAY(0)) as x_37) AS num_slow_count,
  (SELECT
  MAX(MagicalEntangle(Num.col0, x_67.value)) AS logica_value
FROM
  t_37_Num AS Num, JSON_EACH(JSON_ARRAY(0)) as x_67) AS num_max,
  (SELECT
  SUM(MagicalEntangle(1, x_137.value)) AS logica_value
FROM
  t_37_Num AS t_89_Num, JSON_EACH(JSON_ARRAY(0)) as x_137) AS num_count;
