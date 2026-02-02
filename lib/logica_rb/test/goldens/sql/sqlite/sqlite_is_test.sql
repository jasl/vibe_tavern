SELECT
  JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6) AS col0,
  (SELECT
  ArgMin(JSON_EXTRACT(MagicalEntangle(JSON_OBJECT('arg', x_16.value, 'value', (JSON_EXTRACT(JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6), '$[' || x_16.value || ']') IS null)), x_17.value), "$.value"), JSON_EXTRACT(MagicalEntangle(JSON_OBJECT('arg', x_16.value, 'value', (JSON_EXTRACT(JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6), '$[' || x_16.value || ']') IS null)), x_17.value), "$.arg"), null) AS logica_value
FROM
  JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < JSON_ARRAY_LENGTH(JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6))) select n from t) where n < JSON_ARRAY_LENGTH(JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6)))) as x_16, JSON_EACH(JSON_ARRAY(0)) as x_17) AS col1,
  (SELECT
  ArgMin(JSON_EXTRACT(MagicalEntangle(JSON_OBJECT('arg', x_37.value, 'value', (JSON_EXTRACT(JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6), '$[' || x_37.value || ']') IS NOT null)), x_38.value), "$.value"), JSON_EXTRACT(MagicalEntangle(JSON_OBJECT('arg', x_37.value, 'value', (JSON_EXTRACT(JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6), '$[' || x_37.value || ']') IS NOT null)), x_38.value), "$.arg"), null) AS logica_value
FROM
  JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < JSON_ARRAY_LENGTH(JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6))) select n from t) where n < JSON_ARRAY_LENGTH(JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6)))) as x_37, JSON_EACH(JSON_ARRAY(0)) as x_38) AS col2,
  (SELECT
  JSON_GROUP_ARRAY(MagicalEntangle(x_55.value, x_56.value)) AS logica_value
FROM
  JSON_EACH(JSON_ARRAY(1, 2, 3, null, 4, null, 5, 6)) as x_55, JSON_EACH(JSON_ARRAY(0)) as x_56
WHERE
  (x_55.value IS NOT null)) AS col3;
