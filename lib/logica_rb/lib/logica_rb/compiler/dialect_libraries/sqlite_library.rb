# frozen_string_literal: true

module LogicaRb
  module Compiler
    module DialectLibraries
      module SqliteLibrary
        SAFE_LIBRARY = <<~LOGICA
          ->(left:, right:) = {arg: left, value: right};
          `=`(left:, right:) = right :- left == right;

          Arrow(left, right) = arrow :-
            left == arrow.arg,
            right == arrow.value;

          ArgMin(arr) = Element(
              SqlExpr("ArgMin({a}, {v}, 1)", {a:, v:}), 0) :- Arrow(a, v) == arr;

          ArgMax(arr) = Element(
              SqlExpr("ArgMax({a}, {v}, 1)", {a:, v:}), 0) :- Arrow(a, v) == arr;

          ArgMinK(arr, k) =#{' '}
              SqlExpr("ArgMin({a}, {v}, {k})", {a:, v:, k:}) :-
            Arrow(a, v) == arr;

          ArgMaxK(arr, k) =
              SqlExpr("ArgMax({a}, {v}, {k})", {a:, v:, k:}) :- Arrow(a, v) == arr;

          Array(arr) =
              SqlExpr("ArgMin({v}, {a}, null)", {a:, v:}) :- Arrow(a, v) == arr;#{' '}

          Fingerprint(s) = SqlExpr("Fingerprint({s})", {s:});

          AssembleRecord(field_values) = SqlExpr("AssembleRecord({field_values})", {field_values:});

          DisassembleRecord(record) = SqlExpr("DisassembleRecord({record})", {record:});

          Char(code) = SqlExpr("CHAR({code})", {code:});
        LOGICA

        FULL_LIBRARY = <<~LOGICA
          ->(left:, right:) = {arg: left, value: right};
          `=`(left:, right:) = right :- left == right;

          Arrow(left, right) = arrow :-
            left == arrow.arg,
            right == arrow.value;

          PrintToConsole(message) :- 1 == SqlExpr("PrintToConsole({message})", {message:});

          ArgMin(arr) = Element(
              SqlExpr("ArgMin({a}, {v}, 1)", {a:, v:}), 0) :- Arrow(a, v) == arr;

          ArgMax(arr) = Element(
              SqlExpr("ArgMax({a}, {v}, 1)", {a:, v:}), 0) :- Arrow(a, v) == arr;

          ArgMinK(arr, k) =#{' '}
              SqlExpr("ArgMin({a}, {v}, {k})", {a:, v:, k:}) :-
            Arrow(a, v) == arr;

          ArgMaxK(arr, k) =
              SqlExpr("ArgMax({a}, {v}, {k})", {a:, v:, k:}) :- Arrow(a, v) == arr;

          Array(arr) =
              SqlExpr("ArgMin({v}, {a}, null)", {a:, v:}) :- Arrow(a, v) == arr;#{' '}

          ReadFile(filename) = SqlExpr("ReadFile({filename})", {filename:});

          ReadJson(filename) = ReadFile(filename);

          WriteFile(filename, content:) = SqlExpr("WriteFile({filename}, {content})",
                                                  {filename:, content:});

          Fingerprint(s) = SqlExpr("Fingerprint({s})", {s:});

          Intelligence(command) = SqlExpr("Intelligence({command})", {command:});

          RunClingo(script) = SqlExpr("RunClingo({script})", {script:});

          RunClingoFile(filename) = SqlExpr("RunClingoFile({filename})", {filename:});

          AssembleRecord(field_values) = SqlExpr("AssembleRecord({field_values})", {field_values:});

          DisassembleRecord(record) = SqlExpr("DisassembleRecord({record})", {record:});

          Char(code) = SqlExpr("CHAR({code})", {code:});
        LOGICA

        LIBRARY = FULL_LIBRARY
      end
    end
  end
end
