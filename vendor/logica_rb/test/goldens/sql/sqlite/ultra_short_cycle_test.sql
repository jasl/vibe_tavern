WITH t_8_F_r0 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS logica_value
) AS UNUSED_TABLE_NAME  ),
t_7_F_r1 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS logica_value UNION ALL
  
    SELECT
      F_r0.col0 AS col0,
      ((F_r0.logica_value) + (1)) AS logica_value
    FROM
      t_8_F_r0 AS F_r0
) AS UNUSED_TABLE_NAME  ),
t_6_F_r2 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS logica_value UNION ALL
  
    SELECT
      F_r1.col0 AS col0,
      ((F_r1.logica_value) + (1)) AS logica_value
    FROM
      t_7_F_r1 AS F_r1
) AS UNUSED_TABLE_NAME  ),
t_5_F_r3 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS logica_value UNION ALL
  
    SELECT
      F_r2.col0 AS col0,
      ((F_r2.logica_value) + (1)) AS logica_value
    FROM
      t_6_F_r2 AS F_r2
) AS UNUSED_TABLE_NAME  ),
t_4_F_r4 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS logica_value UNION ALL
  
    SELECT
      F_r3.col0 AS col0,
      ((F_r3.logica_value) + (1)) AS logica_value
    FROM
      t_5_F_r3 AS F_r3
) AS UNUSED_TABLE_NAME  ),
t_3_F_r5 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS logica_value UNION ALL
  
    SELECT
      F_r4.col0 AS col0,
      ((F_r4.logica_value) + (1)) AS logica_value
    FROM
      t_4_F_r4 AS F_r4
) AS UNUSED_TABLE_NAME  ),
t_2_F_r6 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS logica_value UNION ALL
  
    SELECT
      F_r5.col0 AS col0,
      ((F_r5.logica_value) + (1)) AS logica_value
    FROM
      t_3_F_r5 AS F_r5
) AS UNUSED_TABLE_NAME  ),
t_1_F_r7 AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS logica_value UNION ALL
  
    SELECT
      F_r6.col0 AS col0,
      ((F_r6.logica_value) + (1)) AS logica_value
    FROM
      t_2_F_r6 AS F_r6
) AS UNUSED_TABLE_NAME  ),
t_0_F AS (SELECT * FROM (
  
    SELECT
      0 AS col0,
      0 AS logica_value UNION ALL
  
    SELECT
      F_r7.col0 AS col0,
      ((F_r7.logica_value) + (1)) AS logica_value
    FROM
      t_1_F_r7 AS F_r7
) AS UNUSED_TABLE_NAME  ),
t_17_Q_r0 AS (SELECT * FROM (
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_16_Q_r1 AS (SELECT * FROM (
  
    SELECT
      Q_r0.col0 AS col0
    FROM
      t_17_Q_r0 AS Q_r0 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_15_Q_r2 AS (SELECT * FROM (
  
    SELECT
      Q_r1.col0 AS col0
    FROM
      t_16_Q_r1 AS Q_r1 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_14_Q_r3 AS (SELECT * FROM (
  
    SELECT
      Q_r2.col0 AS col0
    FROM
      t_15_Q_r2 AS Q_r2 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_13_Q_r4 AS (SELECT * FROM (
  
    SELECT
      Q_r3.col0 AS col0
    FROM
      t_14_Q_r3 AS Q_r3 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_12_Q_r5 AS (SELECT * FROM (
  
    SELECT
      Q_r4.col0 AS col0
    FROM
      t_13_Q_r4 AS Q_r4 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_11_Q_r6 AS (SELECT * FROM (
  
    SELECT
      Q_r5.col0 AS col0
    FROM
      t_12_Q_r5 AS Q_r5 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_10_Q_r7 AS (SELECT * FROM (
  
    SELECT
      Q_r6.col0 AS col0
    FROM
      t_11_Q_r6 AS Q_r6 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  ),
t_9_Q AS (SELECT * FROM (
  
    SELECT
      Q_r7.col0 AS col0
    FROM
      t_10_Q_r7 AS Q_r7 UNION ALL
  
    SELECT
      1 AS col0
) AS UNUSED_TABLE_NAME  )
SELECT * FROM (
  
    SELECT
      'F' AS col0,
      F.col0 AS col1,
      F.logica_value AS col2
    FROM
      t_0_F AS F UNION ALL
  
    SELECT
      'Q' AS col0,
      -1 AS col1,
      Q.col0 AS col2
    FROM
      t_9_Q AS Q
) AS UNUSED_TABLE_NAME  ;
