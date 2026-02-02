WITH t_79_Edge AS (SELECT * FROM (
  
    SELECT
      'a' AS col0,
      'b' AS col1 UNION ALL
  
    SELECT
      'b' AS col0,
      'c' AS col1 UNION ALL
  
    SELECT
      'c' AS col0,
      'd' AS col1 UNION ALL
  
    SELECT
      'd' AS col0,
      'e' AS col1 UNION ALL
  
    SELECT
      'd' AS col0,
      'a' AS col1
) AS UNUSED_TABLE_NAME  ),
t_75_OpenPath_MultBodyAggAux_recursive_head_f1 AS (SELECT * FROM (
  
    SELECT
      Edge.col1 AS col0,
      Edge.col0 AS col1,
      JSON_ARRAY(Edge.col1) AS logica_value
    FROM
      t_79_Edge AS Edge UNION ALL
  
    SELECT
      t_80_Edge.col0 AS col0,
      t_80_Edge.col1 AS col1,
      JSON_ARRAY(t_80_Edge.col0) AS logica_value
    FROM
      t_79_Edge AS t_80_Edge
) AS UNUSED_TABLE_NAME  ),
t_70_OpenPath_r0 AS (SELECT
  OpenPath_MultBodyAggAux_recursive_head_f1.col0 AS col0,
  OpenPath_MultBodyAggAux_recursive_head_f1.col1 AS col1,
  JSON_EXTRACT(JSON_EXTRACT(ArgMin(JSON_OBJECT('nodes', OpenPath_MultBodyAggAux_recursive_head_f1.logica_value), JSON_ARRAY_LENGTH(OpenPath_MultBodyAggAux_recursive_head_f1.logica_value), 1), '$[' || 0 || ']'), "$.nodes") AS logica_value
FROM
  t_75_OpenPath_MultBodyAggAux_recursive_head_f1 AS OpenPath_MultBodyAggAux_recursive_head_f1
GROUP BY OpenPath_MultBodyAggAux_recursive_head_f1.col0, OpenPath_MultBodyAggAux_recursive_head_f1.col1),
t_66_OpenPath_MultBodyAggAux_recursive_head_f2 AS (SELECT * FROM (
  
    SELECT
      OpenPath_r0.col0 AS col0,
      t_69_OpenPath_r0.col1 AS col1,
      ARRAY_CONCAT(OpenPath_r0.logica_value, t_69_OpenPath_r0.logica_value) AS logica_value
    FROM
      t_70_OpenPath_r0 AS OpenPath_r0, t_70_OpenPath_r0 AS t_69_OpenPath_r0
    WHERE
      (OpenPath_r0.col0 != t_69_OpenPath_r0.col1) AND
      (t_69_OpenPath_r0.col0 = OpenPath_r0.col1) UNION ALL
  
    SELECT
      t_92_Edge.col1 AS col0,
      t_92_Edge.col0 AS col1,
      JSON_ARRAY(t_92_Edge.col1) AS logica_value
    FROM
      t_79_Edge AS t_92_Edge UNION ALL
  
    SELECT
      t_93_Edge.col0 AS col0,
      t_93_Edge.col1 AS col1,
      JSON_ARRAY(t_93_Edge.col0) AS logica_value
    FROM
      t_79_Edge AS t_93_Edge
) AS UNUSED_TABLE_NAME  ),
t_61_OpenPath_r1 AS (SELECT
  OpenPath_MultBodyAggAux_recursive_head_f2.col0 AS col0,
  OpenPath_MultBodyAggAux_recursive_head_f2.col1 AS col1,
  JSON_EXTRACT(JSON_EXTRACT(ArgMin(JSON_OBJECT('nodes', OpenPath_MultBodyAggAux_recursive_head_f2.logica_value), JSON_ARRAY_LENGTH(OpenPath_MultBodyAggAux_recursive_head_f2.logica_value), 1), '$[' || 0 || ']'), "$.nodes") AS logica_value
FROM
  t_66_OpenPath_MultBodyAggAux_recursive_head_f2 AS OpenPath_MultBodyAggAux_recursive_head_f2
GROUP BY OpenPath_MultBodyAggAux_recursive_head_f2.col0, OpenPath_MultBodyAggAux_recursive_head_f2.col1),
t_57_OpenPath_MultBodyAggAux_recursive_head_f3 AS (SELECT * FROM (
  
    SELECT
      OpenPath_r1.col0 AS col0,
      t_60_OpenPath_r1.col1 AS col1,
      ARRAY_CONCAT(OpenPath_r1.logica_value, t_60_OpenPath_r1.logica_value) AS logica_value
    FROM
      t_61_OpenPath_r1 AS OpenPath_r1, t_61_OpenPath_r1 AS t_60_OpenPath_r1
    WHERE
      (OpenPath_r1.col0 != t_60_OpenPath_r1.col1) AND
      (t_60_OpenPath_r1.col0 = OpenPath_r1.col1) UNION ALL
  
    SELECT
      t_105_Edge.col1 AS col0,
      t_105_Edge.col0 AS col1,
      JSON_ARRAY(t_105_Edge.col1) AS logica_value
    FROM
      t_79_Edge AS t_105_Edge UNION ALL
  
    SELECT
      t_106_Edge.col0 AS col0,
      t_106_Edge.col1 AS col1,
      JSON_ARRAY(t_106_Edge.col0) AS logica_value
    FROM
      t_79_Edge AS t_106_Edge
) AS UNUSED_TABLE_NAME  ),
t_52_OpenPath_r2 AS (SELECT
  OpenPath_MultBodyAggAux_recursive_head_f3.col0 AS col0,
  OpenPath_MultBodyAggAux_recursive_head_f3.col1 AS col1,
  JSON_EXTRACT(JSON_EXTRACT(ArgMin(JSON_OBJECT('nodes', OpenPath_MultBodyAggAux_recursive_head_f3.logica_value), JSON_ARRAY_LENGTH(OpenPath_MultBodyAggAux_recursive_head_f3.logica_value), 1), '$[' || 0 || ']'), "$.nodes") AS logica_value
FROM
  t_57_OpenPath_MultBodyAggAux_recursive_head_f3 AS OpenPath_MultBodyAggAux_recursive_head_f3
GROUP BY OpenPath_MultBodyAggAux_recursive_head_f3.col0, OpenPath_MultBodyAggAux_recursive_head_f3.col1),
t_48_OpenPath_MultBodyAggAux_recursive_head_f4 AS (SELECT * FROM (
  
    SELECT
      OpenPath_r2.col0 AS col0,
      t_51_OpenPath_r2.col1 AS col1,
      ARRAY_CONCAT(OpenPath_r2.logica_value, t_51_OpenPath_r2.logica_value) AS logica_value
    FROM
      t_52_OpenPath_r2 AS OpenPath_r2, t_52_OpenPath_r2 AS t_51_OpenPath_r2
    WHERE
      (OpenPath_r2.col0 != t_51_OpenPath_r2.col1) AND
      (t_51_OpenPath_r2.col0 = OpenPath_r2.col1) UNION ALL
  
    SELECT
      t_118_Edge.col1 AS col0,
      t_118_Edge.col0 AS col1,
      JSON_ARRAY(t_118_Edge.col1) AS logica_value
    FROM
      t_79_Edge AS t_118_Edge UNION ALL
  
    SELECT
      t_119_Edge.col0 AS col0,
      t_119_Edge.col1 AS col1,
      JSON_ARRAY(t_119_Edge.col0) AS logica_value
    FROM
      t_79_Edge AS t_119_Edge
) AS UNUSED_TABLE_NAME  ),
t_43_OpenPath_r3 AS (SELECT
  OpenPath_MultBodyAggAux_recursive_head_f4.col0 AS col0,
  OpenPath_MultBodyAggAux_recursive_head_f4.col1 AS col1,
  JSON_EXTRACT(JSON_EXTRACT(ArgMin(JSON_OBJECT('nodes', OpenPath_MultBodyAggAux_recursive_head_f4.logica_value), JSON_ARRAY_LENGTH(OpenPath_MultBodyAggAux_recursive_head_f4.logica_value), 1), '$[' || 0 || ']'), "$.nodes") AS logica_value
FROM
  t_48_OpenPath_MultBodyAggAux_recursive_head_f4 AS OpenPath_MultBodyAggAux_recursive_head_f4
GROUP BY OpenPath_MultBodyAggAux_recursive_head_f4.col0, OpenPath_MultBodyAggAux_recursive_head_f4.col1),
t_39_OpenPath_MultBodyAggAux_recursive_head_f5 AS (SELECT * FROM (
  
    SELECT
      OpenPath_r3.col0 AS col0,
      t_42_OpenPath_r3.col1 AS col1,
      ARRAY_CONCAT(OpenPath_r3.logica_value, t_42_OpenPath_r3.logica_value) AS logica_value
    FROM
      t_43_OpenPath_r3 AS OpenPath_r3, t_43_OpenPath_r3 AS t_42_OpenPath_r3
    WHERE
      (OpenPath_r3.col0 != t_42_OpenPath_r3.col1) AND
      (t_42_OpenPath_r3.col0 = OpenPath_r3.col1) UNION ALL
  
    SELECT
      t_131_Edge.col1 AS col0,
      t_131_Edge.col0 AS col1,
      JSON_ARRAY(t_131_Edge.col1) AS logica_value
    FROM
      t_79_Edge AS t_131_Edge UNION ALL
  
    SELECT
      t_132_Edge.col0 AS col0,
      t_132_Edge.col1 AS col1,
      JSON_ARRAY(t_132_Edge.col0) AS logica_value
    FROM
      t_79_Edge AS t_132_Edge
) AS UNUSED_TABLE_NAME  ),
t_34_OpenPath_r4 AS (SELECT
  OpenPath_MultBodyAggAux_recursive_head_f5.col0 AS col0,
  OpenPath_MultBodyAggAux_recursive_head_f5.col1 AS col1,
  JSON_EXTRACT(JSON_EXTRACT(ArgMin(JSON_OBJECT('nodes', OpenPath_MultBodyAggAux_recursive_head_f5.logica_value), JSON_ARRAY_LENGTH(OpenPath_MultBodyAggAux_recursive_head_f5.logica_value), 1), '$[' || 0 || ']'), "$.nodes") AS logica_value
FROM
  t_39_OpenPath_MultBodyAggAux_recursive_head_f5 AS OpenPath_MultBodyAggAux_recursive_head_f5
GROUP BY OpenPath_MultBodyAggAux_recursive_head_f5.col0, OpenPath_MultBodyAggAux_recursive_head_f5.col1),
t_30_OpenPath_MultBodyAggAux_recursive_head_f6 AS (SELECT * FROM (
  
    SELECT
      OpenPath_r4.col0 AS col0,
      t_33_OpenPath_r4.col1 AS col1,
      ARRAY_CONCAT(OpenPath_r4.logica_value, t_33_OpenPath_r4.logica_value) AS logica_value
    FROM
      t_34_OpenPath_r4 AS OpenPath_r4, t_34_OpenPath_r4 AS t_33_OpenPath_r4
    WHERE
      (OpenPath_r4.col0 != t_33_OpenPath_r4.col1) AND
      (t_33_OpenPath_r4.col0 = OpenPath_r4.col1) UNION ALL
  
    SELECT
      t_144_Edge.col1 AS col0,
      t_144_Edge.col0 AS col1,
      JSON_ARRAY(t_144_Edge.col1) AS logica_value
    FROM
      t_79_Edge AS t_144_Edge UNION ALL
  
    SELECT
      t_145_Edge.col0 AS col0,
      t_145_Edge.col1 AS col1,
      JSON_ARRAY(t_145_Edge.col0) AS logica_value
    FROM
      t_79_Edge AS t_145_Edge
) AS UNUSED_TABLE_NAME  ),
t_25_OpenPath_r5 AS (SELECT
  OpenPath_MultBodyAggAux_recursive_head_f6.col0 AS col0,
  OpenPath_MultBodyAggAux_recursive_head_f6.col1 AS col1,
  JSON_EXTRACT(JSON_EXTRACT(ArgMin(JSON_OBJECT('nodes', OpenPath_MultBodyAggAux_recursive_head_f6.logica_value), JSON_ARRAY_LENGTH(OpenPath_MultBodyAggAux_recursive_head_f6.logica_value), 1), '$[' || 0 || ']'), "$.nodes") AS logica_value
FROM
  t_30_OpenPath_MultBodyAggAux_recursive_head_f6 AS OpenPath_MultBodyAggAux_recursive_head_f6
GROUP BY OpenPath_MultBodyAggAux_recursive_head_f6.col0, OpenPath_MultBodyAggAux_recursive_head_f6.col1),
t_21_OpenPath_MultBodyAggAux_recursive_head_f7 AS (SELECT * FROM (
  
    SELECT
      OpenPath_r5.col0 AS col0,
      t_24_OpenPath_r5.col1 AS col1,
      ARRAY_CONCAT(OpenPath_r5.logica_value, t_24_OpenPath_r5.logica_value) AS logica_value
    FROM
      t_25_OpenPath_r5 AS OpenPath_r5, t_25_OpenPath_r5 AS t_24_OpenPath_r5
    WHERE
      (OpenPath_r5.col0 != t_24_OpenPath_r5.col1) AND
      (t_24_OpenPath_r5.col0 = OpenPath_r5.col1) UNION ALL
  
    SELECT
      t_157_Edge.col1 AS col0,
      t_157_Edge.col0 AS col1,
      JSON_ARRAY(t_157_Edge.col1) AS logica_value
    FROM
      t_79_Edge AS t_157_Edge UNION ALL
  
    SELECT
      t_158_Edge.col0 AS col0,
      t_158_Edge.col1 AS col1,
      JSON_ARRAY(t_158_Edge.col0) AS logica_value
    FROM
      t_79_Edge AS t_158_Edge
) AS UNUSED_TABLE_NAME  ),
t_16_OpenPath_r6 AS (SELECT
  OpenPath_MultBodyAggAux_recursive_head_f7.col0 AS col0,
  OpenPath_MultBodyAggAux_recursive_head_f7.col1 AS col1,
  JSON_EXTRACT(JSON_EXTRACT(ArgMin(JSON_OBJECT('nodes', OpenPath_MultBodyAggAux_recursive_head_f7.logica_value), JSON_ARRAY_LENGTH(OpenPath_MultBodyAggAux_recursive_head_f7.logica_value), 1), '$[' || 0 || ']'), "$.nodes") AS logica_value
FROM
  t_21_OpenPath_MultBodyAggAux_recursive_head_f7 AS OpenPath_MultBodyAggAux_recursive_head_f7
GROUP BY OpenPath_MultBodyAggAux_recursive_head_f7.col0, OpenPath_MultBodyAggAux_recursive_head_f7.col1),
t_12_OpenPath_MultBodyAggAux_recursive_head_f8 AS (SELECT * FROM (
  
    SELECT
      OpenPath_r6.col0 AS col0,
      t_15_OpenPath_r6.col1 AS col1,
      ARRAY_CONCAT(OpenPath_r6.logica_value, t_15_OpenPath_r6.logica_value) AS logica_value
    FROM
      t_16_OpenPath_r6 AS OpenPath_r6, t_16_OpenPath_r6 AS t_15_OpenPath_r6
    WHERE
      (OpenPath_r6.col0 != t_15_OpenPath_r6.col1) AND
      (t_15_OpenPath_r6.col0 = OpenPath_r6.col1) UNION ALL
  
    SELECT
      t_170_Edge.col1 AS col0,
      t_170_Edge.col0 AS col1,
      JSON_ARRAY(t_170_Edge.col1) AS logica_value
    FROM
      t_79_Edge AS t_170_Edge UNION ALL
  
    SELECT
      t_171_Edge.col0 AS col0,
      t_171_Edge.col1 AS col1,
      JSON_ARRAY(t_171_Edge.col0) AS logica_value
    FROM
      t_79_Edge AS t_171_Edge
) AS UNUSED_TABLE_NAME  ),
t_7_OpenPath_r7 AS (SELECT
  OpenPath_MultBodyAggAux_recursive_head_f8.col0 AS col0,
  OpenPath_MultBodyAggAux_recursive_head_f8.col1 AS col1,
  JSON_EXTRACT(JSON_EXTRACT(ArgMin(JSON_OBJECT('nodes', OpenPath_MultBodyAggAux_recursive_head_f8.logica_value), JSON_ARRAY_LENGTH(OpenPath_MultBodyAggAux_recursive_head_f8.logica_value), 1), '$[' || 0 || ']'), "$.nodes") AS logica_value
FROM
  t_12_OpenPath_MultBodyAggAux_recursive_head_f8 AS OpenPath_MultBodyAggAux_recursive_head_f8
GROUP BY OpenPath_MultBodyAggAux_recursive_head_f8.col0, OpenPath_MultBodyAggAux_recursive_head_f8.col1),
t_3_OpenPath_MultBodyAggAux_recursive_head_f9 AS (SELECT * FROM (
  
    SELECT
      OpenPath_r7.col0 AS col0,
      t_6_OpenPath_r7.col1 AS col1,
      ARRAY_CONCAT(OpenPath_r7.logica_value, t_6_OpenPath_r7.logica_value) AS logica_value
    FROM
      t_7_OpenPath_r7 AS OpenPath_r7, t_7_OpenPath_r7 AS t_6_OpenPath_r7
    WHERE
      (OpenPath_r7.col0 != t_6_OpenPath_r7.col1) AND
      (t_6_OpenPath_r7.col0 = OpenPath_r7.col1) UNION ALL
  
    SELECT
      t_183_Edge.col1 AS col0,
      t_183_Edge.col0 AS col1,
      JSON_ARRAY(t_183_Edge.col1) AS logica_value
    FROM
      t_79_Edge AS t_183_Edge UNION ALL
  
    SELECT
      t_184_Edge.col0 AS col0,
      t_184_Edge.col1 AS col1,
      JSON_ARRAY(t_184_Edge.col0) AS logica_value
    FROM
      t_79_Edge AS t_184_Edge
) AS UNUSED_TABLE_NAME  ),
t_0_OpenPath AS (SELECT
  OpenPath_MultBodyAggAux_recursive_head_f9.col0 AS col0,
  OpenPath_MultBodyAggAux_recursive_head_f9.col1 AS col1,
  JSON_EXTRACT(JSON_EXTRACT(ArgMin(JSON_OBJECT('nodes', OpenPath_MultBodyAggAux_recursive_head_f9.logica_value), JSON_ARRAY_LENGTH(OpenPath_MultBodyAggAux_recursive_head_f9.logica_value), 1), '$[' || 0 || ']'), "$.nodes") AS logica_value
FROM
  t_3_OpenPath_MultBodyAggAux_recursive_head_f9 AS OpenPath_MultBodyAggAux_recursive_head_f9
GROUP BY OpenPath_MultBodyAggAux_recursive_head_f9.col0, OpenPath_MultBodyAggAux_recursive_head_f9.col1)
SELECT
  OpenPath.col0 AS col0,
  OpenPath.col1 AS col1,
  OpenPath.logica_value AS col2
FROM
  t_0_OpenPath AS OpenPath;
