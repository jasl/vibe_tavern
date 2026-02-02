SELECT
  JOIN_STRINGS((SELECT
  JSON_GROUP_ARRAY(MagicalEntangle(x_34.value, x_35.value)) AS logica_value
FROM
  JSON_EACH(ReadFile('/tmp/sqlite_file_test_data.txt')) as x_34, JSON_EACH(JSON_ARRAY(0)) as x_35
WHERE
  (x_34.value > 10)), '/') AS col0
FROM
  (SELECT 'singleton' as s) as unused_singleton
WHERE
  ('OK' = WriteFile('/tmp/sqlite_file_test_data.txt', (SELECT
    JSON_GROUP_ARRAY(MagicalEntangle(((x_40.value) * (2)), x_41.value)) AS logica_value
  FROM
    JSON_EACH((select json_group_array(n) from (with recursive t as(select 0 as n union all select n + 1 as n from t where n + 1 < 10) select n from t) where n < 10)) as x_40, JSON_EACH(JSON_ARRAY(0)) as x_41)));
