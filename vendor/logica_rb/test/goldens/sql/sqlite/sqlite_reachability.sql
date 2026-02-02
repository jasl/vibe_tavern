WITH t_55_G AS (SELECT * FROM (
  
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
      3 AS col0,
      5 AS col1 UNION ALL
  
    SELECT
      1 AS col0,
      8 AS col1
) AS UNUSED_TABLE_NAME  ),
t_54_C_MultBodyAggAux AS (SELECT * FROM (
  
    SELECT
      G.col0 AS col0,
      G.col1 AS col1
    FROM
      t_55_G AS G UNION ALL
  
    SELECT
      t_56_G.col1 AS col0,
      t_56_G.col0 AS col1
    FROM
      t_55_G AS t_56_G
) AS UNUSED_TABLE_NAME  ),
t_53_C AS (SELECT
  C_MultBodyAggAux.col0 AS col0,
  C_MultBodyAggAux.col1 AS col1
FROM
  t_54_C_MultBodyAggAux AS C_MultBodyAggAux
GROUP BY C_MultBodyAggAux.col0, C_MultBodyAggAux.col1),
t_49_Path_MultBodyAggAux_recursive_head_f1 AS (SELECT * FROM (
  
    SELECT
      C.col0 AS source,
      C.col1 AS target,
      1 AS length,
      JSON_OBJECT('arg', JSON_ARRAY(C.col0), 'value', 1) AS path
    FROM
      t_53_C AS C
) AS UNUSED_TABLE_NAME  ),
t_46_Path_r0 AS (SELECT
  Path_MultBodyAggAux_recursive_head_f1.source AS source,
  Path_MultBodyAggAux_recursive_head_f1.target AS target,
  MIN(Path_MultBodyAggAux_recursive_head_f1.length) AS length,
  JSON_EXTRACT(ArgMin(JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f1.path, "$.arg"), JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f1.path, "$.value"), 1), '$[' || 0 || ']') AS path
FROM
  t_49_Path_MultBodyAggAux_recursive_head_f1 AS Path_MultBodyAggAux_recursive_head_f1
GROUP BY Path_MultBodyAggAux_recursive_head_f1.source, Path_MultBodyAggAux_recursive_head_f1.target),
t_43_Path_MultBodyAggAux_recursive_head_f2 AS (SELECT * FROM (
  
    SELECT
      Path_r0.source AS source,
      t_44_Path_r0.target AS target,
      ((Path_r0.length) + (t_44_Path_r0.length)) AS length,
      JSON_OBJECT('arg', ARRAY_CONCAT(Path_r0.path, t_44_Path_r0.path), 'value', ((Path_r0.length) + (t_44_Path_r0.length))) AS path
    FROM
      t_46_Path_r0 AS Path_r0, t_46_Path_r0 AS t_44_Path_r0
    WHERE
      (t_44_Path_r0.source = Path_r0.target) UNION ALL
  
    SELECT
      t_68_C.col0 AS source,
      t_68_C.col1 AS target,
      1 AS length,
      JSON_OBJECT('arg', JSON_ARRAY(t_68_C.col0), 'value', 1) AS path
    FROM
      t_53_C AS t_68_C
) AS UNUSED_TABLE_NAME  ),
t_40_Path_r1 AS (SELECT
  Path_MultBodyAggAux_recursive_head_f2.source AS source,
  Path_MultBodyAggAux_recursive_head_f2.target AS target,
  MIN(Path_MultBodyAggAux_recursive_head_f2.length) AS length,
  JSON_EXTRACT(ArgMin(JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f2.path, "$.arg"), JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f2.path, "$.value"), 1), '$[' || 0 || ']') AS path
FROM
  t_43_Path_MultBodyAggAux_recursive_head_f2 AS Path_MultBodyAggAux_recursive_head_f2
GROUP BY Path_MultBodyAggAux_recursive_head_f2.source, Path_MultBodyAggAux_recursive_head_f2.target),
t_37_Path_MultBodyAggAux_recursive_head_f3 AS (SELECT * FROM (
  
    SELECT
      Path_r1.source AS source,
      t_38_Path_r1.target AS target,
      ((Path_r1.length) + (t_38_Path_r1.length)) AS length,
      JSON_OBJECT('arg', ARRAY_CONCAT(Path_r1.path, t_38_Path_r1.path), 'value', ((Path_r1.length) + (t_38_Path_r1.length))) AS path
    FROM
      t_40_Path_r1 AS Path_r1, t_40_Path_r1 AS t_38_Path_r1
    WHERE
      (t_38_Path_r1.source = Path_r1.target) UNION ALL
  
    SELECT
      t_78_C.col0 AS source,
      t_78_C.col1 AS target,
      1 AS length,
      JSON_OBJECT('arg', JSON_ARRAY(t_78_C.col0), 'value', 1) AS path
    FROM
      t_53_C AS t_78_C
) AS UNUSED_TABLE_NAME  ),
t_34_Path_r2 AS (SELECT
  Path_MultBodyAggAux_recursive_head_f3.source AS source,
  Path_MultBodyAggAux_recursive_head_f3.target AS target,
  MIN(Path_MultBodyAggAux_recursive_head_f3.length) AS length,
  JSON_EXTRACT(ArgMin(JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f3.path, "$.arg"), JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f3.path, "$.value"), 1), '$[' || 0 || ']') AS path
FROM
  t_37_Path_MultBodyAggAux_recursive_head_f3 AS Path_MultBodyAggAux_recursive_head_f3
GROUP BY Path_MultBodyAggAux_recursive_head_f3.source, Path_MultBodyAggAux_recursive_head_f3.target),
t_31_Path_MultBodyAggAux_recursive_head_f4 AS (SELECT * FROM (
  
    SELECT
      Path_r2.source AS source,
      t_32_Path_r2.target AS target,
      ((Path_r2.length) + (t_32_Path_r2.length)) AS length,
      JSON_OBJECT('arg', ARRAY_CONCAT(Path_r2.path, t_32_Path_r2.path), 'value', ((Path_r2.length) + (t_32_Path_r2.length))) AS path
    FROM
      t_34_Path_r2 AS Path_r2, t_34_Path_r2 AS t_32_Path_r2
    WHERE
      (t_32_Path_r2.source = Path_r2.target) UNION ALL
  
    SELECT
      t_88_C.col0 AS source,
      t_88_C.col1 AS target,
      1 AS length,
      JSON_OBJECT('arg', JSON_ARRAY(t_88_C.col0), 'value', 1) AS path
    FROM
      t_53_C AS t_88_C
) AS UNUSED_TABLE_NAME  ),
t_28_Path_r3 AS (SELECT
  Path_MultBodyAggAux_recursive_head_f4.source AS source,
  Path_MultBodyAggAux_recursive_head_f4.target AS target,
  MIN(Path_MultBodyAggAux_recursive_head_f4.length) AS length,
  JSON_EXTRACT(ArgMin(JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f4.path, "$.arg"), JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f4.path, "$.value"), 1), '$[' || 0 || ']') AS path
FROM
  t_31_Path_MultBodyAggAux_recursive_head_f4 AS Path_MultBodyAggAux_recursive_head_f4
GROUP BY Path_MultBodyAggAux_recursive_head_f4.source, Path_MultBodyAggAux_recursive_head_f4.target),
t_25_Path_MultBodyAggAux_recursive_head_f5 AS (SELECT * FROM (
  
    SELECT
      Path_r3.source AS source,
      t_26_Path_r3.target AS target,
      ((Path_r3.length) + (t_26_Path_r3.length)) AS length,
      JSON_OBJECT('arg', ARRAY_CONCAT(Path_r3.path, t_26_Path_r3.path), 'value', ((Path_r3.length) + (t_26_Path_r3.length))) AS path
    FROM
      t_28_Path_r3 AS Path_r3, t_28_Path_r3 AS t_26_Path_r3
    WHERE
      (t_26_Path_r3.source = Path_r3.target) UNION ALL
  
    SELECT
      t_98_C.col0 AS source,
      t_98_C.col1 AS target,
      1 AS length,
      JSON_OBJECT('arg', JSON_ARRAY(t_98_C.col0), 'value', 1) AS path
    FROM
      t_53_C AS t_98_C
) AS UNUSED_TABLE_NAME  ),
t_22_Path_r4 AS (SELECT
  Path_MultBodyAggAux_recursive_head_f5.source AS source,
  Path_MultBodyAggAux_recursive_head_f5.target AS target,
  MIN(Path_MultBodyAggAux_recursive_head_f5.length) AS length,
  JSON_EXTRACT(ArgMin(JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f5.path, "$.arg"), JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f5.path, "$.value"), 1), '$[' || 0 || ']') AS path
FROM
  t_25_Path_MultBodyAggAux_recursive_head_f5 AS Path_MultBodyAggAux_recursive_head_f5
GROUP BY Path_MultBodyAggAux_recursive_head_f5.source, Path_MultBodyAggAux_recursive_head_f5.target),
t_19_Path_MultBodyAggAux_recursive_head_f6 AS (SELECT * FROM (
  
    SELECT
      Path_r4.source AS source,
      t_20_Path_r4.target AS target,
      ((Path_r4.length) + (t_20_Path_r4.length)) AS length,
      JSON_OBJECT('arg', ARRAY_CONCAT(Path_r4.path, t_20_Path_r4.path), 'value', ((Path_r4.length) + (t_20_Path_r4.length))) AS path
    FROM
      t_22_Path_r4 AS Path_r4, t_22_Path_r4 AS t_20_Path_r4
    WHERE
      (t_20_Path_r4.source = Path_r4.target) UNION ALL
  
    SELECT
      t_108_C.col0 AS source,
      t_108_C.col1 AS target,
      1 AS length,
      JSON_OBJECT('arg', JSON_ARRAY(t_108_C.col0), 'value', 1) AS path
    FROM
      t_53_C AS t_108_C
) AS UNUSED_TABLE_NAME  ),
t_16_Path_r5 AS (SELECT
  Path_MultBodyAggAux_recursive_head_f6.source AS source,
  Path_MultBodyAggAux_recursive_head_f6.target AS target,
  MIN(Path_MultBodyAggAux_recursive_head_f6.length) AS length,
  JSON_EXTRACT(ArgMin(JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f6.path, "$.arg"), JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f6.path, "$.value"), 1), '$[' || 0 || ']') AS path
FROM
  t_19_Path_MultBodyAggAux_recursive_head_f6 AS Path_MultBodyAggAux_recursive_head_f6
GROUP BY Path_MultBodyAggAux_recursive_head_f6.source, Path_MultBodyAggAux_recursive_head_f6.target),
t_13_Path_MultBodyAggAux_recursive_head_f7 AS (SELECT * FROM (
  
    SELECT
      Path_r5.source AS source,
      t_14_Path_r5.target AS target,
      ((Path_r5.length) + (t_14_Path_r5.length)) AS length,
      JSON_OBJECT('arg', ARRAY_CONCAT(Path_r5.path, t_14_Path_r5.path), 'value', ((Path_r5.length) + (t_14_Path_r5.length))) AS path
    FROM
      t_16_Path_r5 AS Path_r5, t_16_Path_r5 AS t_14_Path_r5
    WHERE
      (t_14_Path_r5.source = Path_r5.target) UNION ALL
  
    SELECT
      t_118_C.col0 AS source,
      t_118_C.col1 AS target,
      1 AS length,
      JSON_OBJECT('arg', JSON_ARRAY(t_118_C.col0), 'value', 1) AS path
    FROM
      t_53_C AS t_118_C
) AS UNUSED_TABLE_NAME  ),
t_10_Path_r6 AS (SELECT
  Path_MultBodyAggAux_recursive_head_f7.source AS source,
  Path_MultBodyAggAux_recursive_head_f7.target AS target,
  MIN(Path_MultBodyAggAux_recursive_head_f7.length) AS length,
  JSON_EXTRACT(ArgMin(JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f7.path, "$.arg"), JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f7.path, "$.value"), 1), '$[' || 0 || ']') AS path
FROM
  t_13_Path_MultBodyAggAux_recursive_head_f7 AS Path_MultBodyAggAux_recursive_head_f7
GROUP BY Path_MultBodyAggAux_recursive_head_f7.source, Path_MultBodyAggAux_recursive_head_f7.target),
t_7_Path_MultBodyAggAux_recursive_head_f8 AS (SELECT * FROM (
  
    SELECT
      Path_r6.source AS source,
      t_8_Path_r6.target AS target,
      ((Path_r6.length) + (t_8_Path_r6.length)) AS length,
      JSON_OBJECT('arg', ARRAY_CONCAT(Path_r6.path, t_8_Path_r6.path), 'value', ((Path_r6.length) + (t_8_Path_r6.length))) AS path
    FROM
      t_10_Path_r6 AS Path_r6, t_10_Path_r6 AS t_8_Path_r6
    WHERE
      (t_8_Path_r6.source = Path_r6.target) UNION ALL
  
    SELECT
      t_128_C.col0 AS source,
      t_128_C.col1 AS target,
      1 AS length,
      JSON_OBJECT('arg', JSON_ARRAY(t_128_C.col0), 'value', 1) AS path
    FROM
      t_53_C AS t_128_C
) AS UNUSED_TABLE_NAME  ),
t_4_Path_r7 AS (SELECT
  Path_MultBodyAggAux_recursive_head_f8.source AS source,
  Path_MultBodyAggAux_recursive_head_f8.target AS target,
  MIN(Path_MultBodyAggAux_recursive_head_f8.length) AS length,
  JSON_EXTRACT(ArgMin(JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f8.path, "$.arg"), JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f8.path, "$.value"), 1), '$[' || 0 || ']') AS path
FROM
  t_7_Path_MultBodyAggAux_recursive_head_f8 AS Path_MultBodyAggAux_recursive_head_f8
GROUP BY Path_MultBodyAggAux_recursive_head_f8.source, Path_MultBodyAggAux_recursive_head_f8.target),
t_1_Path_MultBodyAggAux_recursive_head_f9 AS (SELECT * FROM (
  
    SELECT
      Path_r7.source AS source,
      t_2_Path_r7.target AS target,
      ((Path_r7.length) + (t_2_Path_r7.length)) AS length,
      JSON_OBJECT('arg', ARRAY_CONCAT(Path_r7.path, t_2_Path_r7.path), 'value', ((Path_r7.length) + (t_2_Path_r7.length))) AS path
    FROM
      t_4_Path_r7 AS Path_r7, t_4_Path_r7 AS t_2_Path_r7
    WHERE
      (t_2_Path_r7.source = Path_r7.target) UNION ALL
  
    SELECT
      t_138_C.col0 AS source,
      t_138_C.col1 AS target,
      1 AS length,
      JSON_OBJECT('arg', JSON_ARRAY(t_138_C.col0), 'value', 1) AS path
    FROM
      t_53_C AS t_138_C
) AS UNUSED_TABLE_NAME  ),
t_0_Path AS (SELECT
  Path_MultBodyAggAux_recursive_head_f9.source AS source,
  Path_MultBodyAggAux_recursive_head_f9.target AS target,
  MIN(Path_MultBodyAggAux_recursive_head_f9.length) AS length,
  JSON_EXTRACT(ArgMin(JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f9.path, "$.arg"), JSON_EXTRACT(Path_MultBodyAggAux_recursive_head_f9.path, "$.value"), 1), '$[' || 0 || ']') AS path
FROM
  t_1_Path_MultBodyAggAux_recursive_head_f9 AS Path_MultBodyAggAux_recursive_head_f9
GROUP BY Path_MultBodyAggAux_recursive_head_f9.source, Path_MultBodyAggAux_recursive_head_f9.target)
SELECT
  Path.source AS source,
  Path.target AS target,
  ARRAY_CONCAT(Path.path, JSON_ARRAY(Path.target)) AS final_path
FROM
  t_0_Path AS Path
WHERE
  (Path.source != Path.target);
