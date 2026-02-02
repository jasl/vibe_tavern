WITH t_17_A_MultBodyAggAux_f1 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_16_A_fr0 AS (SELECT
  A_MultBodyAggAux_f1.col0 AS col0,
  MAX(A_MultBodyAggAux_f1.logica_value) AS logica_value
FROM
  t_17_A_MultBodyAggAux_f1 AS A_MultBodyAggAux_f1
GROUP BY A_MultBodyAggAux_f1.col0),
t_20_B_MultBodyAggAux_f2 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_19_B_fr0 AS (SELECT
  B_MultBodyAggAux_f2.col0 AS col0,
  MAX(B_MultBodyAggAux_f2.logica_value) AS logica_value
FROM
  t_20_B_MultBodyAggAux_f2 AS B_MultBodyAggAux_f2
GROUP BY B_MultBodyAggAux_f2.col0),
t_15_A_MultBodyAggAux_f4 AS (SELECT * FROM (
  
    SELECT
      ((A_fr0.col0) + (1)) AS col0,
      ((A_fr0.logica_value) + (B_fr0.logica_value)) AS logica_value
    FROM
      t_16_A_fr0 AS A_fr0, t_19_B_fr0 AS B_fr0
    WHERE
      (B_fr0.col0 = A_fr0.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_14_A_fr1 AS (SELECT
  A_MultBodyAggAux_f4.col0 AS col0,
  MAX(A_MultBodyAggAux_f4.logica_value) AS logica_value
FROM
  t_15_A_MultBodyAggAux_f4 AS A_MultBodyAggAux_f4
GROUP BY A_MultBodyAggAux_f4.col0),
t_24_B_MultBodyAggAux_f3 AS (SELECT * FROM (
  
    SELECT
      ((t_25_A_fr0.col0) + (1)) AS col0,
      ((t_25_A_fr0.logica_value) * (t_26_B_fr0.logica_value)) AS logica_value
    FROM
      t_16_A_fr0 AS t_25_A_fr0, t_19_B_fr0 AS t_26_B_fr0
    WHERE
      (t_26_B_fr0.col0 = t_25_A_fr0.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_23_B_fr1 AS (SELECT
  B_MultBodyAggAux_f3.col0 AS col0,
  MAX(B_MultBodyAggAux_f3.logica_value) AS logica_value
FROM
  t_24_B_MultBodyAggAux_f3 AS B_MultBodyAggAux_f3
GROUP BY B_MultBodyAggAux_f3.col0),
t_13_A_MultBodyAggAux_f5 AS (SELECT * FROM (
  
    SELECT
      ((A_fr1.col0) + (1)) AS col0,
      ((A_fr1.logica_value) + (B_fr1.logica_value)) AS logica_value
    FROM
      t_14_A_fr1 AS A_fr1, t_23_B_fr1 AS B_fr1
    WHERE
      (B_fr1.col0 = A_fr1.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_12_A_fr2 AS (SELECT
  A_MultBodyAggAux_f5.col0 AS col0,
  MAX(A_MultBodyAggAux_f5.logica_value) AS logica_value
FROM
  t_13_A_MultBodyAggAux_f5 AS A_MultBodyAggAux_f5
GROUP BY A_MultBodyAggAux_f5.col0),
t_34_B_MultBodyAggAux_f6 AS (SELECT * FROM (
  
    SELECT
      ((t_35_A_fr1.col0) + (1)) AS col0,
      ((t_35_A_fr1.logica_value) * (t_36_B_fr1.logica_value)) AS logica_value
    FROM
      t_14_A_fr1 AS t_35_A_fr1, t_23_B_fr1 AS t_36_B_fr1
    WHERE
      (t_36_B_fr1.col0 = t_35_A_fr1.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_33_B_fr2 AS (SELECT
  B_MultBodyAggAux_f6.col0 AS col0,
  MAX(B_MultBodyAggAux_f6.logica_value) AS logica_value
FROM
  t_34_B_MultBodyAggAux_f6 AS B_MultBodyAggAux_f6
GROUP BY B_MultBodyAggAux_f6.col0),
t_11_A_MultBodyAggAux_f8 AS (SELECT * FROM (
  
    SELECT
      ((A_fr2.col0) + (1)) AS col0,
      ((A_fr2.logica_value) + (B_fr2.logica_value)) AS logica_value
    FROM
      t_12_A_fr2 AS A_fr2, t_33_B_fr2 AS B_fr2
    WHERE
      (B_fr2.col0 = A_fr2.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_10_A_fr3 AS (SELECT
  A_MultBodyAggAux_f8.col0 AS col0,
  MAX(A_MultBodyAggAux_f8.logica_value) AS logica_value
FROM
  t_11_A_MultBodyAggAux_f8 AS A_MultBodyAggAux_f8
GROUP BY A_MultBodyAggAux_f8.col0),
t_44_B_MultBodyAggAux_f7 AS (SELECT * FROM (
  
    SELECT
      ((t_45_A_fr2.col0) + (1)) AS col0,
      ((t_45_A_fr2.logica_value) * (t_46_B_fr2.logica_value)) AS logica_value
    FROM
      t_12_A_fr2 AS t_45_A_fr2, t_33_B_fr2 AS t_46_B_fr2
    WHERE
      (t_46_B_fr2.col0 = t_45_A_fr2.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_43_B_fr3 AS (SELECT
  B_MultBodyAggAux_f7.col0 AS col0,
  MAX(B_MultBodyAggAux_f7.logica_value) AS logica_value
FROM
  t_44_B_MultBodyAggAux_f7 AS B_MultBodyAggAux_f7
GROUP BY B_MultBodyAggAux_f7.col0),
t_9_A_MultBodyAggAux_f9 AS (SELECT * FROM (
  
    SELECT
      ((A_fr3.col0) + (1)) AS col0,
      ((A_fr3.logica_value) + (B_fr3.logica_value)) AS logica_value
    FROM
      t_10_A_fr3 AS A_fr3, t_43_B_fr3 AS B_fr3
    WHERE
      (B_fr3.col0 = A_fr3.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_8_A_fr4 AS (SELECT
  A_MultBodyAggAux_f9.col0 AS col0,
  MAX(A_MultBodyAggAux_f9.logica_value) AS logica_value
FROM
  t_9_A_MultBodyAggAux_f9 AS A_MultBodyAggAux_f9
GROUP BY A_MultBodyAggAux_f9.col0),
t_54_B_MultBodyAggAux_f10 AS (SELECT * FROM (
  
    SELECT
      ((t_55_A_fr3.col0) + (1)) AS col0,
      ((t_55_A_fr3.logica_value) * (t_56_B_fr3.logica_value)) AS logica_value
    FROM
      t_10_A_fr3 AS t_55_A_fr3, t_43_B_fr3 AS t_56_B_fr3
    WHERE
      (t_56_B_fr3.col0 = t_55_A_fr3.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_53_B_fr4 AS (SELECT
  B_MultBodyAggAux_f10.col0 AS col0,
  MAX(B_MultBodyAggAux_f10.logica_value) AS logica_value
FROM
  t_54_B_MultBodyAggAux_f10 AS B_MultBodyAggAux_f10
GROUP BY B_MultBodyAggAux_f10.col0),
t_7_A_MultBodyAggAux_f12 AS (SELECT * FROM (
  
    SELECT
      ((A_fr4.col0) + (1)) AS col0,
      ((A_fr4.logica_value) + (B_fr4.logica_value)) AS logica_value
    FROM
      t_8_A_fr4 AS A_fr4, t_53_B_fr4 AS B_fr4
    WHERE
      (B_fr4.col0 = A_fr4.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_6_A_fr5 AS (SELECT
  A_MultBodyAggAux_f12.col0 AS col0,
  MAX(A_MultBodyAggAux_f12.logica_value) AS logica_value
FROM
  t_7_A_MultBodyAggAux_f12 AS A_MultBodyAggAux_f12
GROUP BY A_MultBodyAggAux_f12.col0),
t_64_B_MultBodyAggAux_f11 AS (SELECT * FROM (
  
    SELECT
      ((t_65_A_fr4.col0) + (1)) AS col0,
      ((t_65_A_fr4.logica_value) * (t_66_B_fr4.logica_value)) AS logica_value
    FROM
      t_8_A_fr4 AS t_65_A_fr4, t_53_B_fr4 AS t_66_B_fr4
    WHERE
      (t_66_B_fr4.col0 = t_65_A_fr4.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_63_B_fr5 AS (SELECT
  B_MultBodyAggAux_f11.col0 AS col0,
  MAX(B_MultBodyAggAux_f11.logica_value) AS logica_value
FROM
  t_64_B_MultBodyAggAux_f11 AS B_MultBodyAggAux_f11
GROUP BY B_MultBodyAggAux_f11.col0),
t_5_A_MultBodyAggAux_f13 AS (SELECT * FROM (
  
    SELECT
      ((A_fr5.col0) + (1)) AS col0,
      ((A_fr5.logica_value) + (B_fr5.logica_value)) AS logica_value
    FROM
      t_6_A_fr5 AS A_fr5, t_63_B_fr5 AS B_fr5
    WHERE
      (B_fr5.col0 = A_fr5.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_4_A_fr6 AS (SELECT
  A_MultBodyAggAux_f13.col0 AS col0,
  MAX(A_MultBodyAggAux_f13.logica_value) AS logica_value
FROM
  t_5_A_MultBodyAggAux_f13 AS A_MultBodyAggAux_f13
GROUP BY A_MultBodyAggAux_f13.col0),
t_74_B_MultBodyAggAux_f14 AS (SELECT * FROM (
  
    SELECT
      ((t_75_A_fr5.col0) + (1)) AS col0,
      ((t_75_A_fr5.logica_value) * (t_76_B_fr5.logica_value)) AS logica_value
    FROM
      t_6_A_fr5 AS t_75_A_fr5, t_63_B_fr5 AS t_76_B_fr5
    WHERE
      (t_76_B_fr5.col0 = t_75_A_fr5.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_73_B_fr6 AS (SELECT
  B_MultBodyAggAux_f14.col0 AS col0,
  MAX(B_MultBodyAggAux_f14.logica_value) AS logica_value
FROM
  t_74_B_MultBodyAggAux_f14 AS B_MultBodyAggAux_f14
GROUP BY B_MultBodyAggAux_f14.col0),
t_3_A_MultBodyAggAux_f16 AS (SELECT * FROM (
  
    SELECT
      ((A_fr6.col0) + (1)) AS col0,
      ((A_fr6.logica_value) + (B_fr6.logica_value)) AS logica_value
    FROM
      t_4_A_fr6 AS A_fr6, t_73_B_fr6 AS B_fr6
    WHERE
      (B_fr6.col0 = A_fr6.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_2_A_fr7 AS (SELECT
  A_MultBodyAggAux_f16.col0 AS col0,
  MAX(A_MultBodyAggAux_f16.logica_value) AS logica_value
FROM
  t_3_A_MultBodyAggAux_f16 AS A_MultBodyAggAux_f16
GROUP BY A_MultBodyAggAux_f16.col0),
t_84_B_MultBodyAggAux_f15 AS (SELECT * FROM (
  
    SELECT
      ((t_85_A_fr6.col0) + (1)) AS col0,
      ((t_85_A_fr6.logica_value) * (t_86_B_fr6.logica_value)) AS logica_value
    FROM
      t_4_A_fr6 AS t_85_A_fr6, t_73_B_fr6 AS t_86_B_fr6
    WHERE
      (t_86_B_fr6.col0 = t_85_A_fr6.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_83_B_fr7 AS (SELECT
  B_MultBodyAggAux_f15.col0 AS col0,
  MAX(B_MultBodyAggAux_f15.logica_value) AS logica_value
FROM
  t_84_B_MultBodyAggAux_f15 AS B_MultBodyAggAux_f15
GROUP BY B_MultBodyAggAux_f15.col0),
t_1_A_MultBodyAggAux_f17 AS (SELECT * FROM (
  
    SELECT
      ((A_fr7.col0) + (1)) AS col0,
      ((A_fr7.logica_value) + (B_fr7.logica_value)) AS logica_value
    FROM
      t_2_A_fr7 AS A_fr7, t_83_B_fr7 AS B_fr7
    WHERE
      (B_fr7.col0 = A_fr7.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_0_A AS (SELECT
  A_MultBodyAggAux_f17.col0 AS col0,
  MAX(A_MultBodyAggAux_f17.logica_value) AS logica_value
FROM
  t_1_A_MultBodyAggAux_f17 AS A_MultBodyAggAux_f17
GROUP BY A_MultBodyAggAux_f17.col0),
t_94_B_MultBodyAggAux_f18 AS (SELECT * FROM (
  
    SELECT
      ((t_95_A_fr7.col0) + (1)) AS col0,
      ((t_95_A_fr7.logica_value) * (t_96_B_fr7.logica_value)) AS logica_value
    FROM
      t_2_A_fr7 AS t_95_A_fr7, t_83_B_fr7 AS t_96_B_fr7
    WHERE
      (t_96_B_fr7.col0 = t_95_A_fr7.col0) UNION ALL
  
    SELECT
      0 AS col0,
      1 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_93_B AS (SELECT
  B_MultBodyAggAux_f18.col0 AS col0,
  MAX(B_MultBodyAggAux_f18.logica_value) AS logica_value
FROM
  t_94_B_MultBodyAggAux_f18 AS B_MultBodyAggAux_f18
GROUP BY B_MultBodyAggAux_f18.col0)
SELECT
  A.col0 AS n,
  A.logica_value AS a,
  B.logica_value AS b
FROM
  t_0_A AS A, t_93_B AS B
WHERE
  (B.col0 = A.col0);
