# frozen_string_literal: true

module LogicaRb
  module Compiler
    module DialectLibraries
      module PsqlLibrary
        SAFE_LIBRARY = <<~LOGICA
          ->(left:, right:) = {arg: left, value: right};
          `=`(left:, right:) = right :- left == right;

          ArgMin(a) = (SqlExpr("(ARRAY_AGG({arg} order by {value}))[1]",
                               {arg: {argpod: a.arg}, value: a.value})).argpod;

          ArgMax(a) = (SqlExpr(
            "(ARRAY_AGG({arg} order by {value} desc))[1]",
            {arg: {argpod: a.arg}, value: a.value})).argpod;

          ArgMaxK(a, l) = SqlExpr(
            "(ARRAY_AGG({arg} order by {value} desc))[1:{lim}]",
            {arg: a.arg, value: a.value, lim: l});

          ArgMinK(a, l) = SqlExpr(
            "(ARRAY_AGG({arg} order by {value}))[1:{lim}]",
            {arg: a.arg, value: a.value, lim: l});

          Array(a) = SqlExpr(
            "ARRAY_AGG({value} order by {arg})",
            {arg: a.arg, value: a.value});

          RecordAsJson(r) = SqlExpr(
            "ROW_TO_JSON({r})", {r:});

          Fingerprint(s) = SqlExpr("('x' || substr(md5({s}), 1, 16))::bit(64)::bigint", {s:});

          Chr(x) = SqlExpr("Chr({x})", {x:});

          Num(a) = a;
          Str(a) = a;
        LOGICA

        FULL_LIBRARY = <<~LOGICA
          ->(left:, right:) = {arg: left, value: right};
          `=`(left:, right:) = right :- left == right;

          ArgMin(a) = (SqlExpr("(ARRAY_AGG({arg} order by {value}))[1]",
                               {arg: {argpod: a.arg}, value: a.value})).argpod;

          ArgMax(a) = (SqlExpr(
            "(ARRAY_AGG({arg} order by {value} desc))[1]",
            {arg: {argpod: a.arg}, value: a.value})).argpod;

          ArgMaxK(a, l) = SqlExpr(
            "(ARRAY_AGG({arg} order by {value} desc))[1:{lim}]",
            {arg: a.arg, value: a.value, lim: l});

          ArgMinK(a, l) = SqlExpr(
            "(ARRAY_AGG({arg} order by {value}))[1:{lim}]",
            {arg: a.arg, value: a.value, lim: l});

          Array(a) = SqlExpr(
            "ARRAY_AGG({value} order by {arg})",
            {arg: a.arg, value: a.value});

          RecordAsJson(r) = SqlExpr(
            "ROW_TO_JSON({r})", {r:});

          Fingerprint(s) = SqlExpr("('x' || substr(md5({s}), 1, 16))::bit(64)::bigint", {s:});

          ReadFile(filename) = SqlExpr("pg_read_file({filename})", {filename:});

          Chr(x) = SqlExpr("Chr({x})", {x:});

          Num(a) = a;
          Str(a) = a;
        LOGICA

        LIBRARY = FULL_LIBRARY
      end
    end
  end
end
