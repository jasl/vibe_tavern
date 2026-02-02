SELECT
  JSON_EXTRACT(JSON_ARRAY('a', 'b', 'c', 'd', 'e'), '$[' || x_1.value || ']') AS col0
FROM
  JSON_EACH(JSON_ARRAY(1, 2, 4)) as x_1;
