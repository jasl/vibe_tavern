WITH t_1_Employee AS (SELECT * FROM (
  
    SELECT
      'A' AS name,
      'Kirkland' AS city UNION ALL
  
    SELECT
      'B' AS name,
      'Seattle' AS city UNION ALL
  
    SELECT
      'C' AS name,
      'Kirkland' AS city UNION ALL
  
    SELECT
      'D' AS name,
      'Los Angeles' AS city
) AS UNUSED_TABLE_NAME  ),
t_2_Office AS (SELECT * FROM (
  
    SELECT
      'Kirkland' AS city,
      'Washington' AS state UNION ALL
  
    SELECT
      'Seattle' AS city,
      'Washington' AS state UNION ALL
  
    SELECT
      'Los Angeles' AS city,
      'California' AS state
) AS UNUSED_TABLE_NAME  ),
t_3_State AS (SELECT
  t_4_Office.state AS col0
FROM
  t_2_Office AS t_4_Office
GROUP BY t_4_Office.state),
t_0_EmployeesInState AS (SELECT
  State.col0 AS state,
  (SELECT
  SUM(MagicalEntangle(1, x_10.value)) AS logica_value
FROM
  t_1_Employee AS Employee, t_2_Office AS Office, JSON_EACH(JSON_ARRAY(0)) as x_10
WHERE
  (Office.city = Employee.city) AND
  (Office.state = State.col0)) AS employee_count
FROM
  t_3_State AS State)
SELECT
  EmployeesInState.*
FROM
  t_0_EmployeesInState AS EmployeesInState;
