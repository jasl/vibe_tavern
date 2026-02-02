WITH t_5_F_recursive_head_f1 AS (SELECT * FROM (
  
    SELECT
      'g' AS col0
) AS UNUSED_TABLE_NAME  ),
t_3_F_recursive_head_f2 AS (SELECT * FROM (
  
    SELECT
      F_recursive_head_f1.col0 AS col0
    FROM
      t_5_F_recursive_head_f1 AS F_recursive_head_f1, t_5_F_recursive_head_f1 AS t_4_F_recursive_head_f1
    WHERE
      (t_4_F_recursive_head_f1.col0 = F_recursive_head_f1.col0) UNION ALL
  
    SELECT
      'g' AS col0
) AS UNUSED_TABLE_NAME  ),
t_1_F_recursive_head_f3 AS (SELECT * FROM (
  
    SELECT
      F_recursive_head_f2.col0 AS col0
    FROM
      t_3_F_recursive_head_f2 AS F_recursive_head_f2, t_3_F_recursive_head_f2 AS t_2_F_recursive_head_f2
    WHERE
      (t_2_F_recursive_head_f2.col0 = F_recursive_head_f2.col0) UNION ALL
  
    SELECT
      'g' AS col0
) AS UNUSED_TABLE_NAME  ),
t_28_F_recursive_head_f5 AS (SELECT * FROM (
  
    SELECT
      t_34_F_recursive_head_f3.col0 AS col0
    FROM
      t_1_F_recursive_head_f3 AS t_34_F_recursive_head_f3, t_1_F_recursive_head_f3 AS t_35_F_recursive_head_f3
    WHERE
      (t_35_F_recursive_head_f3.col0 = t_34_F_recursive_head_f3.col0) UNION ALL
  
    SELECT
      'g' AS col0
) AS UNUSED_TABLE_NAME  ),
t_85_L_recursive_head_f10 AS (SELECT * FROM (
  
    SELECT
      'l' AS col0
) AS UNUSED_TABLE_NAME  ),
t_81_K_r0 AS (SELECT * FROM (
  
    SELECT
      t_84_F_recursive_head_f5.col0 AS col0
    FROM
      t_28_F_recursive_head_f5 AS t_84_F_recursive_head_f5 UNION ALL
  
    SELECT
      L_recursive_head_f10.col0 AS col0
    FROM
      t_85_L_recursive_head_f10 AS L_recursive_head_f10
) AS UNUSED_TABLE_NAME  ),
t_80_L_recursive_head_f11 AS (SELECT * FROM (
  
    SELECT
      'l' AS col0 UNION ALL
  
    SELECT
      K_r0.col0 AS col0
    FROM
      t_81_K_r0 AS K_r0
) AS UNUSED_TABLE_NAME  ),
t_76_K_r1 AS (SELECT * FROM (
  
    SELECT
      t_79_F_recursive_head_f5.col0 AS col0
    FROM
      t_28_F_recursive_head_f5 AS t_79_F_recursive_head_f5 UNION ALL
  
    SELECT
      L_recursive_head_f11.col0 AS col0
    FROM
      t_80_L_recursive_head_f11 AS L_recursive_head_f11
) AS UNUSED_TABLE_NAME  ),
t_75_L_recursive_head_f12 AS (SELECT * FROM (
  
    SELECT
      'l' AS col0 UNION ALL
  
    SELECT
      K_r1.col0 AS col0
    FROM
      t_76_K_r1 AS K_r1
) AS UNUSED_TABLE_NAME  ),
t_71_K_r2 AS (SELECT * FROM (
  
    SELECT
      t_74_F_recursive_head_f5.col0 AS col0
    FROM
      t_28_F_recursive_head_f5 AS t_74_F_recursive_head_f5 UNION ALL
  
    SELECT
      L_recursive_head_f12.col0 AS col0
    FROM
      t_75_L_recursive_head_f12 AS L_recursive_head_f12
) AS UNUSED_TABLE_NAME  ),
t_70_L_recursive_head_f13 AS (SELECT * FROM (
  
    SELECT
      'l' AS col0 UNION ALL
  
    SELECT
      K_r2.col0 AS col0
    FROM
      t_71_K_r2 AS K_r2
) AS UNUSED_TABLE_NAME  ),
t_66_K_r3 AS (SELECT * FROM (
  
    SELECT
      t_69_F_recursive_head_f5.col0 AS col0
    FROM
      t_28_F_recursive_head_f5 AS t_69_F_recursive_head_f5 UNION ALL
  
    SELECT
      L_recursive_head_f13.col0 AS col0
    FROM
      t_70_L_recursive_head_f13 AS L_recursive_head_f13
) AS UNUSED_TABLE_NAME  ),
t_65_L_recursive_head_f14 AS (SELECT * FROM (
  
    SELECT
      'l' AS col0 UNION ALL
  
    SELECT
      K_r3.col0 AS col0
    FROM
      t_66_K_r3 AS K_r3
) AS UNUSED_TABLE_NAME  ),
t_61_K_r4 AS (SELECT * FROM (
  
    SELECT
      t_64_F_recursive_head_f5.col0 AS col0
    FROM
      t_28_F_recursive_head_f5 AS t_64_F_recursive_head_f5 UNION ALL
  
    SELECT
      L_recursive_head_f14.col0 AS col0
    FROM
      t_65_L_recursive_head_f14 AS L_recursive_head_f14
) AS UNUSED_TABLE_NAME  ),
t_60_L_recursive_head_f15 AS (SELECT * FROM (
  
    SELECT
      'l' AS col0 UNION ALL
  
    SELECT
      K_r4.col0 AS col0
    FROM
      t_61_K_r4 AS K_r4
) AS UNUSED_TABLE_NAME  ),
t_56_K_r5 AS (SELECT * FROM (
  
    SELECT
      t_59_F_recursive_head_f5.col0 AS col0
    FROM
      t_28_F_recursive_head_f5 AS t_59_F_recursive_head_f5 UNION ALL
  
    SELECT
      L_recursive_head_f15.col0 AS col0
    FROM
      t_60_L_recursive_head_f15 AS L_recursive_head_f15
) AS UNUSED_TABLE_NAME  ),
t_55_L_recursive_head_f16 AS (SELECT * FROM (
  
    SELECT
      'l' AS col0 UNION ALL
  
    SELECT
      K_r5.col0 AS col0
    FROM
      t_56_K_r5 AS K_r5
) AS UNUSED_TABLE_NAME  ),
t_51_K_r6 AS (SELECT * FROM (
  
    SELECT
      t_54_F_recursive_head_f5.col0 AS col0
    FROM
      t_28_F_recursive_head_f5 AS t_54_F_recursive_head_f5 UNION ALL
  
    SELECT
      L_recursive_head_f16.col0 AS col0
    FROM
      t_55_L_recursive_head_f16 AS L_recursive_head_f16
) AS UNUSED_TABLE_NAME  ),
t_50_L_recursive_head_f17 AS (SELECT * FROM (
  
    SELECT
      'l' AS col0 UNION ALL
  
    SELECT
      K_r6.col0 AS col0
    FROM
      t_51_K_r6 AS K_r6
) AS UNUSED_TABLE_NAME  ),
t_38_K_r7 AS (SELECT * FROM (
  
    SELECT
      t_41_F_recursive_head_f5.col0 AS col0
    FROM
      t_28_F_recursive_head_f5 AS t_41_F_recursive_head_f5 UNION ALL
  
    SELECT
      L_recursive_head_f17.col0 AS col0
    FROM
      t_50_L_recursive_head_f17 AS L_recursive_head_f17
) AS UNUSED_TABLE_NAME  ),
t_37_L_recursive_head_f18 AS (SELECT * FROM (
  
    SELECT
      'l' AS col0 UNION ALL
  
    SELECT
      K_r7.col0 AS col0
    FROM
      t_38_K_r7 AS K_r7
) AS UNUSED_TABLE_NAME  ),
t_27_K AS (SELECT * FROM (
  
    SELECT
      F_recursive_head_f5.col0 AS col0
    FROM
      t_28_F_recursive_head_f5 AS F_recursive_head_f5 UNION ALL
  
    SELECT
      L_recursive_head_f18.col0 AS col0
    FROM
      t_37_L_recursive_head_f18 AS L_recursive_head_f18
) AS UNUSED_TABLE_NAME  ),
t_26_L AS (SELECT * FROM (
  
    SELECT
      'l' AS col0 UNION ALL
  
    SELECT
      K.col0 AS col0
    FROM
      t_27_K AS K
) AS UNUSED_TABLE_NAME  )
SELECT * FROM (
  
    SELECT
      F_recursive_head_f3.col0 AS col0
    FROM
      t_1_F_recursive_head_f3 AS F_recursive_head_f3, t_1_F_recursive_head_f3 AS t_0_F_recursive_head_f3
    WHERE
      (t_0_F_recursive_head_f3.col0 = F_recursive_head_f3.col0) UNION ALL
  
    SELECT
      L.col0 AS col0
    FROM
      t_26_L AS L UNION ALL
  
    SELECT
      'i' AS col0
) AS UNUSED_TABLE_NAME  ORDER BY col0 ;
