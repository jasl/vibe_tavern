WITH t_3_Link AS (SELECT * FROM (
  
    SELECT
      'a' AS col0,
      'b' AS col1 UNION ALL
  
    SELECT
      'a' AS col0,
      'c' AS col1 UNION ALL
  
    SELECT
      'c' AS col0,
      'd' AS col1 UNION ALL
  
    SELECT
      'e' AS col0,
      'd' AS col1 UNION ALL
  
    SELECT
      'h' AS col0,
      'd' AS col1 UNION ALL
  
    SELECT
      'd' AS col0,
      'i' AS col1 UNION ALL
  
    SELECT
      'd' AS col0,
      'j' AS col1 UNION ALL
  
    SELECT
      'j' AS col0,
      'd' AS col1 UNION ALL
  
    SELECT
      'i' AS col0,
      'a' AS col1 UNION ALL
  
    SELECT
      'f' AS col0,
      'g' AS col1 UNION ALL
  
    SELECT
      'g' AS col0,
      'f' AS col1
) AS UNUSED_TABLE_NAME  ),
t_2_Vertex_MultBodyAggAux AS (SELECT * FROM (
  
    SELECT
      Link.col0 AS col0
    FROM
      t_3_Link AS Link UNION ALL
  
    SELECT
      t_4_Link.col1 AS col0
    FROM
      t_3_Link AS t_4_Link
) AS UNUSED_TABLE_NAME  ),
t_1_Vertex AS (SELECT
  Vertex_MultBodyAggAux.col0 AS col0
FROM
  t_2_Vertex_MultBodyAggAux AS Vertex_MultBodyAggAux
GROUP BY Vertex_MultBodyAggAux.col0),
t_45_PageRank_MultBodyAggAux_recursive_head_f1 AS (SELECT * FROM (
  
    SELECT
      t_46_Vertex.col0 AS col0,
      1.0 AS logica_value
    FROM
      t_1_Vertex AS t_46_Vertex
) AS UNUSED_TABLE_NAME  ),
t_44_PageRank_r0 AS (SELECT
  PageRank_MultBodyAggAux_recursive_head_f1.col0 AS col0,
  SUM(PageRank_MultBodyAggAux_recursive_head_f1.logica_value) AS logica_value
FROM
  t_45_PageRank_MultBodyAggAux_recursive_head_f1 AS PageRank_MultBodyAggAux_recursive_head_f1
GROUP BY PageRank_MultBodyAggAux_recursive_head_f1.col0),
t_49_Degree AS (SELECT
  t_50_Link.col0 AS col0,
  SUM(1.0) AS logica_value
FROM
  t_3_Link AS t_50_Link
GROUP BY t_50_Link.col0),
t_40_PageRank_MultBodyAggAux_recursive_head_f2 AS (SELECT * FROM (
  
    SELECT
      t_41_Vertex.col0 AS col0,
      1.0 AS logica_value
    FROM
      t_1_Vertex AS t_41_Vertex UNION ALL
  
    SELECT
      t_42_Link.col1 AS col0,
      ((0.5) * (((PageRank_r0.logica_value) / (t_43_Degree.logica_value)))) AS logica_value
    FROM
      t_3_Link AS t_42_Link, t_44_PageRank_r0 AS PageRank_r0, t_49_Degree AS t_43_Degree
    WHERE
      (PageRank_r0.col0 = t_42_Link.col0) AND
      (t_43_Degree.col0 = t_42_Link.col0)
) AS UNUSED_TABLE_NAME  ),
t_39_PageRank_r1 AS (SELECT
  PageRank_MultBodyAggAux_recursive_head_f2.col0 AS col0,
  SUM(PageRank_MultBodyAggAux_recursive_head_f2.logica_value) AS logica_value
FROM
  t_40_PageRank_MultBodyAggAux_recursive_head_f2 AS PageRank_MultBodyAggAux_recursive_head_f2
GROUP BY PageRank_MultBodyAggAux_recursive_head_f2.col0),
t_35_PageRank_MultBodyAggAux_recursive_head_f3 AS (SELECT * FROM (
  
    SELECT
      t_36_Vertex.col0 AS col0,
      1.0 AS logica_value
    FROM
      t_1_Vertex AS t_36_Vertex UNION ALL
  
    SELECT
      t_37_Link.col1 AS col0,
      ((0.5) * (((PageRank_r1.logica_value) / (t_38_Degree.logica_value)))) AS logica_value
    FROM
      t_3_Link AS t_37_Link, t_39_PageRank_r1 AS PageRank_r1, t_49_Degree AS t_38_Degree
    WHERE
      (PageRank_r1.col0 = t_37_Link.col0) AND
      (t_38_Degree.col0 = t_37_Link.col0)
) AS UNUSED_TABLE_NAME  ),
t_34_PageRank_r2 AS (SELECT
  PageRank_MultBodyAggAux_recursive_head_f3.col0 AS col0,
  SUM(PageRank_MultBodyAggAux_recursive_head_f3.logica_value) AS logica_value
FROM
  t_35_PageRank_MultBodyAggAux_recursive_head_f3 AS PageRank_MultBodyAggAux_recursive_head_f3
GROUP BY PageRank_MultBodyAggAux_recursive_head_f3.col0),
t_30_PageRank_MultBodyAggAux_recursive_head_f4 AS (SELECT * FROM (
  
    SELECT
      t_31_Vertex.col0 AS col0,
      1.0 AS logica_value
    FROM
      t_1_Vertex AS t_31_Vertex UNION ALL
  
    SELECT
      t_32_Link.col1 AS col0,
      ((0.5) * (((PageRank_r2.logica_value) / (t_33_Degree.logica_value)))) AS logica_value
    FROM
      t_3_Link AS t_32_Link, t_34_PageRank_r2 AS PageRank_r2, t_49_Degree AS t_33_Degree
    WHERE
      (PageRank_r2.col0 = t_32_Link.col0) AND
      (t_33_Degree.col0 = t_32_Link.col0)
) AS UNUSED_TABLE_NAME  ),
t_29_PageRank_r3 AS (SELECT
  PageRank_MultBodyAggAux_recursive_head_f4.col0 AS col0,
  SUM(PageRank_MultBodyAggAux_recursive_head_f4.logica_value) AS logica_value
FROM
  t_30_PageRank_MultBodyAggAux_recursive_head_f4 AS PageRank_MultBodyAggAux_recursive_head_f4
GROUP BY PageRank_MultBodyAggAux_recursive_head_f4.col0),
t_25_PageRank_MultBodyAggAux_recursive_head_f5 AS (SELECT * FROM (
  
    SELECT
      t_26_Vertex.col0 AS col0,
      1.0 AS logica_value
    FROM
      t_1_Vertex AS t_26_Vertex UNION ALL
  
    SELECT
      t_27_Link.col1 AS col0,
      ((0.5) * (((PageRank_r3.logica_value) / (t_28_Degree.logica_value)))) AS logica_value
    FROM
      t_3_Link AS t_27_Link, t_29_PageRank_r3 AS PageRank_r3, t_49_Degree AS t_28_Degree
    WHERE
      (PageRank_r3.col0 = t_27_Link.col0) AND
      (t_28_Degree.col0 = t_27_Link.col0)
) AS UNUSED_TABLE_NAME  ),
t_24_PageRank_r4 AS (SELECT
  PageRank_MultBodyAggAux_recursive_head_f5.col0 AS col0,
  SUM(PageRank_MultBodyAggAux_recursive_head_f5.logica_value) AS logica_value
FROM
  t_25_PageRank_MultBodyAggAux_recursive_head_f5 AS PageRank_MultBodyAggAux_recursive_head_f5
GROUP BY PageRank_MultBodyAggAux_recursive_head_f5.col0),
t_20_PageRank_MultBodyAggAux_recursive_head_f6 AS (SELECT * FROM (
  
    SELECT
      t_21_Vertex.col0 AS col0,
      1.0 AS logica_value
    FROM
      t_1_Vertex AS t_21_Vertex UNION ALL
  
    SELECT
      t_22_Link.col1 AS col0,
      ((0.5) * (((PageRank_r4.logica_value) / (t_23_Degree.logica_value)))) AS logica_value
    FROM
      t_3_Link AS t_22_Link, t_24_PageRank_r4 AS PageRank_r4, t_49_Degree AS t_23_Degree
    WHERE
      (PageRank_r4.col0 = t_22_Link.col0) AND
      (t_23_Degree.col0 = t_22_Link.col0)
) AS UNUSED_TABLE_NAME  ),
t_19_PageRank_r5 AS (SELECT
  PageRank_MultBodyAggAux_recursive_head_f6.col0 AS col0,
  SUM(PageRank_MultBodyAggAux_recursive_head_f6.logica_value) AS logica_value
FROM
  t_20_PageRank_MultBodyAggAux_recursive_head_f6 AS PageRank_MultBodyAggAux_recursive_head_f6
GROUP BY PageRank_MultBodyAggAux_recursive_head_f6.col0),
t_15_PageRank_MultBodyAggAux_recursive_head_f7 AS (SELECT * FROM (
  
    SELECT
      t_16_Vertex.col0 AS col0,
      1.0 AS logica_value
    FROM
      t_1_Vertex AS t_16_Vertex UNION ALL
  
    SELECT
      t_17_Link.col1 AS col0,
      ((0.5) * (((PageRank_r5.logica_value) / (t_18_Degree.logica_value)))) AS logica_value
    FROM
      t_3_Link AS t_17_Link, t_19_PageRank_r5 AS PageRank_r5, t_49_Degree AS t_18_Degree
    WHERE
      (PageRank_r5.col0 = t_17_Link.col0) AND
      (t_18_Degree.col0 = t_17_Link.col0)
) AS UNUSED_TABLE_NAME  ),
t_14_PageRank_r6 AS (SELECT
  PageRank_MultBodyAggAux_recursive_head_f7.col0 AS col0,
  SUM(PageRank_MultBodyAggAux_recursive_head_f7.logica_value) AS logica_value
FROM
  t_15_PageRank_MultBodyAggAux_recursive_head_f7 AS PageRank_MultBodyAggAux_recursive_head_f7
GROUP BY PageRank_MultBodyAggAux_recursive_head_f7.col0),
t_7_PageRank_MultBodyAggAux_recursive_head_f8 AS (SELECT * FROM (
  
    SELECT
      t_8_Vertex.col0 AS col0,
      1.0 AS logica_value
    FROM
      t_1_Vertex AS t_8_Vertex UNION ALL
  
    SELECT
      t_12_Link.col1 AS col0,
      ((0.5) * (((PageRank_r6.logica_value) / (t_13_Degree.logica_value)))) AS logica_value
    FROM
      t_3_Link AS t_12_Link, t_14_PageRank_r6 AS PageRank_r6, t_49_Degree AS t_13_Degree
    WHERE
      (PageRank_r6.col0 = t_12_Link.col0) AND
      (t_13_Degree.col0 = t_12_Link.col0)
) AS UNUSED_TABLE_NAME  ),
t_6_PageRank_r7 AS (SELECT
  PageRank_MultBodyAggAux_recursive_head_f8.col0 AS col0,
  SUM(PageRank_MultBodyAggAux_recursive_head_f8.logica_value) AS logica_value
FROM
  t_7_PageRank_MultBodyAggAux_recursive_head_f8 AS PageRank_MultBodyAggAux_recursive_head_f8
GROUP BY PageRank_MultBodyAggAux_recursive_head_f8.col0),
t_0_PageRank_MultBodyAggAux_recursive_head_f9 AS (SELECT * FROM (
  
    SELECT
      Vertex.col0 AS col0,
      1.0 AS logica_value
    FROM
      t_1_Vertex AS Vertex UNION ALL
  
    SELECT
      t_5_Link.col1 AS col0,
      ((0.5) * (((PageRank_r7.logica_value) / (Degree.logica_value)))) AS logica_value
    FROM
      t_3_Link AS t_5_Link, t_6_PageRank_r7 AS PageRank_r7, t_49_Degree AS Degree
    WHERE
      (PageRank_r7.col0 = t_5_Link.col0) AND
      (Degree.col0 = t_5_Link.col0)
) AS UNUSED_TABLE_NAME  )
SELECT
  PageRank_MultBodyAggAux_recursive_head_f9.col0 AS col0,
  SUM(PageRank_MultBodyAggAux_recursive_head_f9.logica_value) AS logica_value
FROM
  t_0_PageRank_MultBodyAggAux_recursive_head_f9 AS PageRank_MultBodyAggAux_recursive_head_f9
GROUP BY PageRank_MultBodyAggAux_recursive_head_f9.col0;
