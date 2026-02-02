WITH t_0_TestArrayConcatAgg AS (SELECT
  ARRAY_CONCAT_AGG((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < ((x_35.value) + (1))) select n from t) where n < ((x_35.value) + (1)))) AS logica_value
FROM
  JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 3) select n from t) where n < 3)) as x_35),
t_2_TestArrayConcatAggNull_MultBodyAggAux AS (SELECT * FROM (
  
    SELECT
      (select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < ((x_41.value) + (1))) select n from t) where n < ((x_41.value) + (1))) AS logica_value
    FROM
      JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 3) select n from t) where n < 3)) as x_41 UNION ALL
  
    SELECT
      null AS logica_value
    FROM
      JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 3) select n from t) where n < 3)) as x_43
) AS UNUSED_TABLE_NAME  ),
t_1_TestArrayConcatAggNull AS (SELECT
  ARRAY_CONCAT_AGG(TestArrayConcatAggNull_MultBodyAggAux.logica_value) AS logica_value
FROM
  t_2_TestArrayConcatAggNull_MultBodyAggAux AS TestArrayConcatAggNull_MultBodyAggAux)
SELECT * FROM (
  
    SELECT
      'Set' AS col0,
      JSON_ARRAY_LENGTH((SELECT
      DistinctListAgg(MagicalEntangle(((x_3.value) + (x_4.value)), x_5.value)) AS logica_value
    FROM
      JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 5) select n from t) where n < 5)) as x_3, JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 5) select n from t) where n < 5)) as x_4, JSON_EACH(JSON_ARRAY(0)) as x_5)) AS logica_value UNION ALL
  
    SELECT
      'Sort' AS col0,
      SortList(JSON_ARRAY(6, 3, 2, 5, 1, 4)) AS logica_value UNION ALL
  
    SELECT
      'InList' AS col0,
      (SELECT
      JSON_GROUP_ARRAY(MagicalEntangle(((((x_10.value) || (','))) || (x_11.value)), x_12.value)) AS logica_value
    FROM
      JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 3) select n from t) where n < 3)) as x_10, JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 3) select n from t) where n < 3)) as x_11, JSON_EACH(JSON_ARRAY(0)) as x_12
    WHERE
      (IN_LIST(x_10.value, JSON_ARRAY(((x_11.value) + (1)), ((x_11.value) + (2)))))) AS logica_value UNION ALL
  
    SELECT
      'Fingerprint' AS col0,
      (((SELECT
      SUM(MagicalEntangle(1, x_18.value)) AS logica_value
    FROM
      JSON_EACH((SELECT
        JSON_GROUP_ARRAY(MagicalEntangle(ABS(((Fingerprint(x_21.value)) / (9223372036854775808.))), x_22.value)) AS logica_value
      FROM
        JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 10000) select n from t) where n < 10000)) as x_21, JSON_EACH(JSON_ARRAY(0)) as x_22)) as x_17, JSON_EACH(JSON_ARRAY(0)) as x_18
    WHERE
      (x_17.value < 0.4))) / (10000.)) AS logica_value UNION ALL
  
    SELECT
      'Floor' AS col0,
      (SELECT
      JSON_GROUP_ARRAY(MagicalEntangle(Printf('%.2f->%.2f', ((x_30.value) / (3.0)), FLOOR(((x_30.value) / (3.0)))), x_31.value)) AS logica_value
    FROM
      JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 7) select n from t) where n < 7)) as x_30, JSON_EACH(JSON_ARRAY(0)) as x_31) AS logica_value UNION ALL
  
    SELECT
      'Range2' AS col0,
      (select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 2) select n from t) where n < 2) AS logica_value UNION ALL
  
    SELECT
      'Range0' AS col0,
      (select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 0) select n from t) where n < 0) AS logica_value UNION ALL
  
    SELECT
      'Least' AS col0,
      MIN(5, 3, 6, 4) AS logica_value UNION ALL
  
    SELECT
      'Greatest' AS col0,
      MAX(5, 3, 6, 4) AS logica_value UNION ALL
  
    SELECT
      'ToString' AS col0,
      CAST('fire' AS TEXT) AS logica_value UNION ALL
  
    SELECT
      'ArrayConcatAgg' AS col0,
      TestArrayConcatAgg.logica_value AS logica_value
    FROM
      t_0_TestArrayConcatAgg AS TestArrayConcatAgg UNION ALL
  
    SELECT
      'StringLiteral' AS col0,
      'People''s artist' AS logica_value UNION ALL
  
    SELECT
      'ArrayConcatNull' AS col0,
      ARRAY_CONCAT(JSON_ARRAY(1, 2, 3), null) AS logica_value UNION ALL
  
    SELECT
      'ArrayConcatAggNull' AS col0,
      TestArrayConcatAggNull.logica_value AS logica_value
    FROM
      t_1_TestArrayConcatAggNull AS TestArrayConcatAggNull UNION ALL
  
    SELECT
      'Char' AS col0,
      CHAR(66) AS logica_value
) AS UNUSED_TABLE_NAME  ;
