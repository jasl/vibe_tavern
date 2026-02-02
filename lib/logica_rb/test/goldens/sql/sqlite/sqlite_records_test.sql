WITH t_3_T AS (SELECT * FROM (
  
    SELECT
      1 AS a,
      2 AS b UNION ALL
  
    SELECT
      3 AS a,
      4 AS b
) AS UNUSED_TABLE_NAME  )
SELECT
  JSON_EXTRACT(JSON_OBJECT('a', T.a, 'b', T.b), "$.a") AS a,
  JSON_EXTRACT(JSON_OBJECT('a', T.a, 'b', T.b), "$.b") AS b,
  JSON_OBJECT('a', T.a, 'b', T.b) AS r,
  JSON_EXTRACT(JSON_OBJECT('a', t_0_T.a, 'b', t_0_T.b), "$.a") AS c,
  JSON_OBJECT('two_a', ((2) * (t_1_T.a))) AS two_a_record,
  ((2) * (t_1_T.a)) AS ta,
  JSON_OBJECT('0', 5, 'logica_value', JSON_OBJECT('a', 5, 'b', ((2) * (5)))) AS f
FROM
  t_3_T AS t_0_T, t_3_T AS T, t_3_T AS t_1_T
WHERE
  (JSON_EXTRACT(JSON_OBJECT('a', t_0_T.a, 'b', t_0_T.b), "$.a") = 1) ORDER BY a, ta;
