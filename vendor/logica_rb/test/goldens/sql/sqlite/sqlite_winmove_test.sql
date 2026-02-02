WITH t_2_M AS (SELECT * FROM (
  
    SELECT
      '0' AS col0,
      'a' AS col1 UNION ALL
  
    SELECT
      '0' AS col0,
      '1' AS col1 UNION ALL
  
    SELECT
      '1' AS col0,
      '0' AS col1 UNION ALL
  
    SELECT
      'a' AS col0,
      'b' AS col1 UNION ALL
  
    SELECT
      'a' AS col0,
      'c' AS col1 UNION ALL
  
    SELECT
      'b' AS col0,
      'c' AS col1 UNION ALL
  
    SELECT
      'c' AS col0,
      'd' AS col1 UNION ALL
  
    SELECT
      'd' AS col0,
      'e' AS col1
) AS UNUSED_TABLE_NAME  ),
t_4_V AS (SELECT
  x_21.value AS col0
FROM
  t_2_M AS t_5_M, JSON_EACH(JSON_ARRAY(t_5_M.col0, t_5_M.col1)) as x_21
GROUP BY x_21.value),
t_76_Loss_recursive_head_f1 AS (SELECT * FROM (
  
    SELECT
      t_78_V.col0 AS col0
    FROM
      t_4_V AS t_78_V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_228.value)) AS logica_value
      FROM
        t_2_M AS t_79_M, JSON_EACH(JSON_ARRAY(0)) as x_228
      WHERE
        (t_79_M.col0 = t_78_V.col0)) IS null) UNION ALL
  
    SELECT
      t_81_V.col0 AS col0
    FROM
      t_4_V AS t_81_V
    WHERE
      (CAST((/* nil */ SELECT NULL FROM (SELECT 42 AS MONAD) AS NIRVANA WHERE MONAD = 0) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_243.value)) AS logica_value
      FROM
        t_2_M AS t_83_M, JSON_EACH(JSON_ARRAY(0)) as x_243
      WHERE
        (t_83_M.col0 = t_81_V.col0)))
) AS UNUSED_TABLE_NAME  ),
t_74_Win_r0 AS (SELECT
  t_75_M.col0 AS col0
FROM
  t_2_M AS t_75_M, t_76_Loss_recursive_head_f1 AS Loss_recursive_head_f1
WHERE
  (Loss_recursive_head_f1.col0 = t_75_M.col1)
GROUP BY t_75_M.col0),
t_67_Loss_recursive_head_f2 AS (SELECT * FROM (
  
    SELECT
      t_69_V.col0 AS col0
    FROM
      t_4_V AS t_69_V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_203.value)) AS logica_value
      FROM
        t_2_M AS t_70_M, JSON_EACH(JSON_ARRAY(0)) as x_203
      WHERE
        (t_70_M.col0 = t_69_V.col0)) IS null) UNION ALL
  
    SELECT
      t_72_V.col0 AS col0
    FROM
      t_4_V AS t_72_V
    WHERE
      (CAST((SELECT
        SUM(MagicalEntangle(1, x_215.value)) AS logica_value
      FROM
        t_2_M AS t_73_M, t_74_Win_r0 AS Win_r0, JSON_EACH(JSON_ARRAY(0)) as x_215
      WHERE
        (t_73_M.col0 = t_72_V.col0) AND
        (Win_r0.col0 = t_73_M.col1)) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_246.value)) AS logica_value
      FROM
        t_2_M AS t_84_M, JSON_EACH(JSON_ARRAY(0)) as x_246
      WHERE
        (t_84_M.col0 = t_72_V.col0)))
) AS UNUSED_TABLE_NAME  ),
t_65_Win_r1 AS (SELECT
  t_66_M.col0 AS col0
FROM
  t_2_M AS t_66_M, t_67_Loss_recursive_head_f2 AS Loss_recursive_head_f2
WHERE
  (Loss_recursive_head_f2.col0 = t_66_M.col1)
GROUP BY t_66_M.col0),
t_58_Loss_recursive_head_f3 AS (SELECT * FROM (
  
    SELECT
      t_60_V.col0 AS col0
    FROM
      t_4_V AS t_60_V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_178.value)) AS logica_value
      FROM
        t_2_M AS t_61_M, JSON_EACH(JSON_ARRAY(0)) as x_178
      WHERE
        (t_61_M.col0 = t_60_V.col0)) IS null) UNION ALL
  
    SELECT
      t_63_V.col0 AS col0
    FROM
      t_4_V AS t_63_V
    WHERE
      (CAST((SELECT
        SUM(MagicalEntangle(1, x_190.value)) AS logica_value
      FROM
        t_2_M AS t_64_M, t_65_Win_r1 AS Win_r1, JSON_EACH(JSON_ARRAY(0)) as x_190
      WHERE
        (t_64_M.col0 = t_63_V.col0) AND
        (Win_r1.col0 = t_64_M.col1)) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_249.value)) AS logica_value
      FROM
        t_2_M AS t_85_M, JSON_EACH(JSON_ARRAY(0)) as x_249
      WHERE
        (t_85_M.col0 = t_63_V.col0)))
) AS UNUSED_TABLE_NAME  ),
t_56_Win_r2 AS (SELECT
  t_57_M.col0 AS col0
FROM
  t_2_M AS t_57_M, t_58_Loss_recursive_head_f3 AS Loss_recursive_head_f3
WHERE
  (Loss_recursive_head_f3.col0 = t_57_M.col1)
GROUP BY t_57_M.col0),
t_49_Loss_recursive_head_f4 AS (SELECT * FROM (
  
    SELECT
      t_51_V.col0 AS col0
    FROM
      t_4_V AS t_51_V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_153.value)) AS logica_value
      FROM
        t_2_M AS t_52_M, JSON_EACH(JSON_ARRAY(0)) as x_153
      WHERE
        (t_52_M.col0 = t_51_V.col0)) IS null) UNION ALL
  
    SELECT
      t_54_V.col0 AS col0
    FROM
      t_4_V AS t_54_V
    WHERE
      (CAST((SELECT
        SUM(MagicalEntangle(1, x_165.value)) AS logica_value
      FROM
        t_2_M AS t_55_M, t_56_Win_r2 AS Win_r2, JSON_EACH(JSON_ARRAY(0)) as x_165
      WHERE
        (t_55_M.col0 = t_54_V.col0) AND
        (Win_r2.col0 = t_55_M.col1)) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_252.value)) AS logica_value
      FROM
        t_2_M AS t_86_M, JSON_EACH(JSON_ARRAY(0)) as x_252
      WHERE
        (t_86_M.col0 = t_54_V.col0)))
) AS UNUSED_TABLE_NAME  ),
t_47_Win_r3 AS (SELECT
  t_48_M.col0 AS col0
FROM
  t_2_M AS t_48_M, t_49_Loss_recursive_head_f4 AS Loss_recursive_head_f4
WHERE
  (Loss_recursive_head_f4.col0 = t_48_M.col1)
GROUP BY t_48_M.col0),
t_40_Loss_recursive_head_f5 AS (SELECT * FROM (
  
    SELECT
      t_42_V.col0 AS col0
    FROM
      t_4_V AS t_42_V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_128.value)) AS logica_value
      FROM
        t_2_M AS t_43_M, JSON_EACH(JSON_ARRAY(0)) as x_128
      WHERE
        (t_43_M.col0 = t_42_V.col0)) IS null) UNION ALL
  
    SELECT
      t_45_V.col0 AS col0
    FROM
      t_4_V AS t_45_V
    WHERE
      (CAST((SELECT
        SUM(MagicalEntangle(1, x_140.value)) AS logica_value
      FROM
        t_2_M AS t_46_M, t_47_Win_r3 AS Win_r3, JSON_EACH(JSON_ARRAY(0)) as x_140
      WHERE
        (t_46_M.col0 = t_45_V.col0) AND
        (Win_r3.col0 = t_46_M.col1)) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_255.value)) AS logica_value
      FROM
        t_2_M AS t_87_M, JSON_EACH(JSON_ARRAY(0)) as x_255
      WHERE
        (t_87_M.col0 = t_45_V.col0)))
) AS UNUSED_TABLE_NAME  ),
t_38_Win_r4 AS (SELECT
  t_39_M.col0 AS col0
FROM
  t_2_M AS t_39_M, t_40_Loss_recursive_head_f5 AS Loss_recursive_head_f5
WHERE
  (Loss_recursive_head_f5.col0 = t_39_M.col1)
GROUP BY t_39_M.col0),
t_31_Loss_recursive_head_f6 AS (SELECT * FROM (
  
    SELECT
      t_33_V.col0 AS col0
    FROM
      t_4_V AS t_33_V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_103.value)) AS logica_value
      FROM
        t_2_M AS t_34_M, JSON_EACH(JSON_ARRAY(0)) as x_103
      WHERE
        (t_34_M.col0 = t_33_V.col0)) IS null) UNION ALL
  
    SELECT
      t_36_V.col0 AS col0
    FROM
      t_4_V AS t_36_V
    WHERE
      (CAST((SELECT
        SUM(MagicalEntangle(1, x_115.value)) AS logica_value
      FROM
        t_2_M AS t_37_M, t_38_Win_r4 AS Win_r4, JSON_EACH(JSON_ARRAY(0)) as x_115
      WHERE
        (t_37_M.col0 = t_36_V.col0) AND
        (Win_r4.col0 = t_37_M.col1)) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_258.value)) AS logica_value
      FROM
        t_2_M AS t_88_M, JSON_EACH(JSON_ARRAY(0)) as x_258
      WHERE
        (t_88_M.col0 = t_36_V.col0)))
) AS UNUSED_TABLE_NAME  ),
t_29_Win_r5 AS (SELECT
  t_30_M.col0 AS col0
FROM
  t_2_M AS t_30_M, t_31_Loss_recursive_head_f6 AS Loss_recursive_head_f6
WHERE
  (Loss_recursive_head_f6.col0 = t_30_M.col1)
GROUP BY t_30_M.col0),
t_22_Loss_recursive_head_f7 AS (SELECT * FROM (
  
    SELECT
      t_24_V.col0 AS col0
    FROM
      t_4_V AS t_24_V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_78.value)) AS logica_value
      FROM
        t_2_M AS t_25_M, JSON_EACH(JSON_ARRAY(0)) as x_78
      WHERE
        (t_25_M.col0 = t_24_V.col0)) IS null) UNION ALL
  
    SELECT
      t_27_V.col0 AS col0
    FROM
      t_4_V AS t_27_V
    WHERE
      (CAST((SELECT
        SUM(MagicalEntangle(1, x_90.value)) AS logica_value
      FROM
        t_2_M AS t_28_M, t_29_Win_r5 AS Win_r5, JSON_EACH(JSON_ARRAY(0)) as x_90
      WHERE
        (t_28_M.col0 = t_27_V.col0) AND
        (Win_r5.col0 = t_28_M.col1)) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_261.value)) AS logica_value
      FROM
        t_2_M AS t_89_M, JSON_EACH(JSON_ARRAY(0)) as x_261
      WHERE
        (t_89_M.col0 = t_27_V.col0)))
) AS UNUSED_TABLE_NAME  ),
t_20_Win_r6 AS (SELECT
  t_21_M.col0 AS col0
FROM
  t_2_M AS t_21_M, t_22_Loss_recursive_head_f7 AS Loss_recursive_head_f7
WHERE
  (Loss_recursive_head_f7.col0 = t_21_M.col1)
GROUP BY t_21_M.col0),
t_13_Loss_recursive_head_f8 AS (SELECT * FROM (
  
    SELECT
      t_15_V.col0 AS col0
    FROM
      t_4_V AS t_15_V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_53.value)) AS logica_value
      FROM
        t_2_M AS t_16_M, JSON_EACH(JSON_ARRAY(0)) as x_53
      WHERE
        (t_16_M.col0 = t_15_V.col0)) IS null) UNION ALL
  
    SELECT
      t_18_V.col0 AS col0
    FROM
      t_4_V AS t_18_V
    WHERE
      (CAST((SELECT
        SUM(MagicalEntangle(1, x_65.value)) AS logica_value
      FROM
        t_2_M AS t_19_M, t_20_Win_r6 AS Win_r6, JSON_EACH(JSON_ARRAY(0)) as x_65
      WHERE
        (t_19_M.col0 = t_18_V.col0) AND
        (Win_r6.col0 = t_19_M.col1)) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_264.value)) AS logica_value
      FROM
        t_2_M AS t_90_M, JSON_EACH(JSON_ARRAY(0)) as x_264
      WHERE
        (t_90_M.col0 = t_18_V.col0)))
) AS UNUSED_TABLE_NAME  ),
t_11_Win_r7 AS (SELECT
  t_12_M.col0 AS col0
FROM
  t_2_M AS t_12_M, t_13_Loss_recursive_head_f8 AS Loss_recursive_head_f8
WHERE
  (Loss_recursive_head_f8.col0 = t_12_M.col1)
GROUP BY t_12_M.col0),
t_3_Loss_recursive_head_f9 AS (SELECT * FROM (
  
    SELECT
      V.col0 AS col0
    FROM
      t_4_V AS V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_24.value)) AS logica_value
      FROM
        t_2_M AS t_6_M, JSON_EACH(JSON_ARRAY(0)) as x_24
      WHERE
        (t_6_M.col0 = V.col0)) IS null) UNION ALL
  
    SELECT
      t_8_V.col0 AS col0
    FROM
      t_4_V AS t_8_V
    WHERE
      (CAST((SELECT
        SUM(MagicalEntangle(1, x_40.value)) AS logica_value
      FROM
        t_2_M AS t_10_M, t_11_Win_r7 AS Win_r7, JSON_EACH(JSON_ARRAY(0)) as x_40
      WHERE
        (t_10_M.col0 = t_8_V.col0) AND
        (Win_r7.col0 = t_10_M.col1)) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_267.value)) AS logica_value
      FROM
        t_2_M AS t_91_M, JSON_EACH(JSON_ARRAY(0)) as x_267
      WHERE
        (t_91_M.col0 = t_8_V.col0)))
) AS UNUSED_TABLE_NAME  ),
t_1_Win AS (SELECT
  M.col0 AS col0
FROM
  t_2_M AS M, t_3_Loss_recursive_head_f9 AS Loss_recursive_head_f9
WHERE
  (Loss_recursive_head_f9.col0 = M.col1)
GROUP BY M.col0),
t_93_Loss AS (SELECT * FROM (
  
    SELECT
      t_95_V.col0 AS col0
    FROM
      t_4_V AS t_95_V
    WHERE
      ((SELECT
        SUM(MagicalEntangle(1, x_284.value)) AS logica_value
      FROM
        t_2_M AS t_96_M, JSON_EACH(JSON_ARRAY(0)) as x_284
      WHERE
        (t_96_M.col0 = t_95_V.col0)) IS null) UNION ALL
  
    SELECT
      t_98_V.col0 AS col0
    FROM
      t_4_V AS t_98_V
    WHERE
      (CAST((SELECT
        SUM(MagicalEntangle(1, x_296.value)) AS logica_value
      FROM
        t_2_M AS t_99_M, t_1_Win AS t_100_Win, JSON_EACH(JSON_ARRAY(0)) as x_296
      WHERE
        (t_99_M.col0 = t_98_V.col0) AND
        (t_100_Win.col0 = t_99_M.col1)) AS INT64) >= (SELECT
        SUM(MagicalEntangle(1, x_551.value)) AS logica_value
      FROM
        t_2_M AS t_191_M, JSON_EACH(JSON_ARRAY(0)) as x_551
      WHERE
        (t_191_M.col0 = t_98_V.col0)))
) AS UNUSED_TABLE_NAME  )
SELECT * FROM (
  
    SELECT
      JSON_OBJECT('arg', Win.col0, 'value', 'win') AS col0
    FROM
      t_1_Win AS Win UNION ALL
  
    SELECT
      JSON_OBJECT('arg', Loss.col0, 'value', 'loss') AS col0
    FROM
      t_93_Loss AS Loss UNION ALL
  
    SELECT
      JSON_OBJECT('arg', t_192_V.col0, 'value', 'draw') AS col0
    FROM
      t_4_V AS t_192_V
    WHERE
      ((SELECT
        MIN(MagicalEntangle(1, x_562.value)) AS logica_value
      FROM
        t_1_Win AS t_194_Win, JSON_EACH(JSON_ARRAY(0)) as x_562
      WHERE
        (t_194_Win.col0 = t_192_V.col0)) IS NULL) AND
      ((SELECT
        MIN(MagicalEntangle(1, x_565.value)) AS logica_value
      FROM
        t_93_Loss AS t_195_Loss, JSON_EACH(JSON_ARRAY(0)) as x_565
      WHERE
        (t_195_Loss.col0 = t_192_V.col0)) IS NULL)
) AS UNUSED_TABLE_NAME  ORDER BY col0 ;
