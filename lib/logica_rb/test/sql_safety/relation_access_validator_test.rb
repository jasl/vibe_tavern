# frozen_string_literal: true

require "test_helper"

class RelationAccessValidatorTest < Minitest::Test
  def validate!(sql, **opts)
    LogicaRb::SqlSafety::RelationAccessValidator.validate!(sql, **opts)
  end

  def test_allows_comma_separated_relations
    validate!(
      "SELECT * FROM bi.orders, bi.orders WHERE 1 = 1",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_rejects_invalid_relation_after_dot
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM public.",
          engine: "psql",
          allowed_relations: ["public.orders"]
        )
      end

    assert_equal :invalid_relation, err.reason
  end

  def test_rejects_when_allowed_relations_is_empty
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM bi.orders",
          engine: "psql",
          allowed_relations: []
        )
      end

    assert_equal :relation_not_allowed, err.reason
  end

  def test_allowed_schemas_empty_rejected
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM orders",
          engine: "psql",
          allowed_schemas: []
        )
      end

    assert_equal :schema_not_allowed, err.reason
  end

  def test_allowed_schemas_must_include_default_schema
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM orders",
          engine: "psql",
          allowed_schemas: ["bi"]
        )
      end

    assert_equal :schema_not_allowed, err.reason
    assert_match(/public/i, err.message)
  end

  def test_skips_join_noise_like_only
    validate!(
      "SELECT * FROM ONLY bi.orders",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_parses_backtick_and_bracket_quoted_relations
    validate!(
      "SELECT * FROM `bi`.`orders`",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )

    validate!(
      "SELECT * FROM [bi].[orders]",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_recursive_cte_with_column_list_is_not_treated_as_relation
    validate!(
      "WITH RECURSIVE t(x) AS (SELECT 1) SELECT * FROM t",
      engine: "psql",
      allowed_relations: []
    )
  end

  def test_allows_explicit_allowlisted_relation
    validate!(
      "SELECT * FROM bi.orders",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_allows_cte_reference
    validate!(
      "WITH t AS (SELECT * FROM bi.orders) SELECT * FROM t",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_rejects_denied_postgres_schemas
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM pg_catalog.pg_class",
          engine: "psql",
          allowed_relations: ["bi.orders"]
        )
      end
    assert_match(/pg_catalog/i, err.message)

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM information_schema.tables",
          engine: "psql",
          allowed_relations: ["bi.orders"]
        )
      end
    assert_match(/information_schema/i, err.message)
  end

  def test_denied_relations_are_denied_even_if_allowlisted_psql
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM pg_catalog.pg_class",
          engine: "psql",
          allowed_relations: ["pg_catalog.pg_class"]
        )
      end

    assert_equal :denied_schema, err.reason
    assert_match(/pg_catalog/i, err.message)

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM pg_catalog.pg_class",
          engine: "psql",
          allowed_schemas: ["pg_catalog"]
        )
      end

    assert_equal :denied_schema, err.reason
    assert_match(/pg_catalog/i, err.message)
  end

  def test_rejects_quoted_denied_schemas
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM \"pg_catalog\".\"pg_class\"",
          engine: "psql",
          allowed_relations: ["bi.orders"]
        )
      end
    assert_equal :denied_schema, err.reason
    assert_match(/pg_catalog/i, err.message)

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM \"sqlite_master\"",
          engine: "sqlite",
          allowed_relations: ["allowed_table"]
        )
      end
    assert_equal :denied_schema, err.reason
    assert_match(/sqlite_master/i, err.message)
  end

  def test_rejects_non_allowlisted_relation
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM secret.orders",
          engine: "psql",
          allowed_relations: ["bi.orders"]
        )
      end

    assert_match(/secret\.orders/i, err.message)
  end

  def test_denied_relations_are_denied_even_if_allowlisted_sqlite
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM sqlite_master",
          engine: "sqlite",
          allowed_relations: ["sqlite_master"]
        )
      end

    assert_equal :denied_schema, err.reason
    assert_match(/sqlite_master/i, err.message)
  end

  def test_does_not_allow_schema_escape_from_bare_table_allowlist
    validate!(
      "SELECT * FROM orders",
      engine: "psql",
      allowed_relations: ["orders"]
    )

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM secret.orders",
          engine: "psql",
          allowed_relations: ["orders"]
        )
      end
    assert_equal :relation_not_allowed, err.reason
    assert_match(/secret\.orders/i, err.message)
  end

  def test_psql_rejects_unqualified_pg_relations_even_if_public_schema_allowed
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM pg_class",
          engine: "psql",
          allowed_schemas: ["public"]
        )
      end

    assert_equal :relation_not_allowed, err.reason
    assert_match(/pg_class/i, err.message)
    assert_match(/pg_catalog/i, err.message)
  end

  def test_psql_rejects_quoted_unqualified_pg_relations
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM \"pg_class\"",
          engine: "psql",
          allowed_schemas: ["public"]
        )
      end

    assert_equal :relation_not_allowed, err.reason
    assert_match(/pg_class/i, err.message)
    assert_match(/pg_catalog/i, err.message)
  end

  def test_psql_schema_qualified_pg_relation_follows_normal_allowlist_logic
    validate!(
      "SELECT * FROM public.pg_class",
      engine: "psql",
      allowed_relations: ["public.pg_class"]
    )

    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM public.pg_class",
          engine: "psql",
          allowed_relations: ["bi.orders"]
        )
      end
    assert_equal :relation_not_allowed, err.reason
    assert_match(/public\.pg_class/i, err.message)
  end

  def test_psql_pg_relation_rule_does_not_trigger_on_strings_or_comments
    validate!(
      "SELECT 'pg_class' AS s FROM bi.orders",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )

    validate!(
      "SELECT * FROM bi.orders -- pg_class\n",
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_handles_quotes_aliases_and_joins
    validate!(
      <<~SQL,
        SELECT o.id
        FROM "bi"."orders" AS o
        JOIN bi.orders o2 ON o2.id = o.id
      SQL
      engine: "psql",
      allowed_relations: ["bi.orders"]
    )
  end

  def test_sqlite_denies_sqlite_master
    err =
      assert_raises(LogicaRb::SqlSafety::Violation) do
        validate!(
          "SELECT * FROM sqlite_master",
          engine: "sqlite",
          allowed_relations: ["allowed_table"]
        )
      end

    assert_match(/sqlite_master/i, err.message)
  end
end
