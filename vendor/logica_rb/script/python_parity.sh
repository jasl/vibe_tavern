#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MANIFEST_PATH="${ROOT_DIR}/test/fixtures_manifest.yml"
FIXTURES_ROOT="${ROOT_DIR}/test/fixtures"
GOLDENS_ROOT="${ROOT_DIR}/test/goldens/sql"

PYTHON_SQL_ROOT="${ROOT_DIR}/tmp/python_sql"
PARITY_TMP_ROOT="${ROOT_DIR}/tmp/python_parity"
UPSTREAM_ROOT="${PARITY_TMP_ROOT}/upstream_logica"
UPSTREAM_REPO_URL="https://github.com/EvgSkv/logica.git"

commit="${UPSTREAM_LOGICA_COMMIT:-}"
if [[ -z "${commit}" && -f "${ROOT_DIR}/UPSTREAM_LOGICA_COMMIT" ]]; then
  commit="$(tr -d '[:space:]' < "${ROOT_DIR}/UPSTREAM_LOGICA_COMMIT")"
fi

if [[ -z "${commit}" ]]; then
  echo "Error: missing upstream commit pin. Set UPSTREAM_LOGICA_COMMIT or create UPSTREAM_LOGICA_COMMIT file." >&2
  exit 2
fi

command -v git >/dev/null || { echo "Error: git is required." >&2; exit 2; }
command -v python3 >/dev/null || { echo "Error: python3 is required." >&2; exit 2; }
command -v ruby >/dev/null || { echo "Error: ruby is required to parse ${MANIFEST_PATH}." >&2; exit 2; }

mkdir -p "${PARITY_TMP_ROOT}" "${PYTHON_SQL_ROOT}/sqlite" "${PYTHON_SQL_ROOT}/psql"

normalize_sql() {
  python3 - "$1" <<'PY'
import sys

path = sys.argv[1]
s = open(path, "r", encoding="utf-8", errors="replace").read()
import re

out = []
i = 0
in_single = False
in_double = False

def sort_logica_type_segments(text: str) -> str:
  marker = "-- Logica type:"
  if marker not in text:
    return text

  parts = text.split(marker)
  head = parts[0]
  chunks = parts[1:]

  parsed = []
  for chunk in chunks:
    idx = chunk.find(" end if;")
    if idx == -1:
      return text
    seg = chunk[: idx + len(" end if;")]
    tail = chunk[idx + len(" end if;") :]

    name = ""
    seg_stripped = seg.lstrip()
    if seg_stripped:
      name = seg_stripped.split(None, 1)[0]
    parsed.append((name, seg, tail))

  parsed.sort(key=lambda t: t[0])

  out_parts = [head]
  for name, seg, tail in parsed:
    out_parts.append(marker)
    out_parts.append(seg)
    out_parts.append(tail)

  return "".join(out_parts)

def drop_redundant_relation_aliases(text: str) -> str:
  return re.sub(r'\b([A-Za-z_][A-Za-z0-9_]*)\b AS \1\b', r'\1', text)

while i < len(s):
  ch = s[i]

  if in_single:
    out.append(ch)
    if ch == "'":
      if i + 1 < len(s) and s[i + 1] == "'":
        out.append("'")
        i += 1
      else:
        in_single = False
    i += 1
    continue

  if in_double:
    out.append(ch)
    if ch == '"':
      if i + 1 < len(s) and s[i + 1] == '"':
        out.append('"')
        i += 1
      else:
        in_double = False
    i += 1
    continue

  if ch == "'":
    in_single = True
    out.append(ch)
    i += 1
    continue

  if ch == '"':
    in_double = True
    out.append(ch)
    i += 1
    continue

  # Drop unstable temp prefixes like `t_28_Foo` -> `Foo`.
  if (
    ch == "t"
    and i + 2 < len(s)
    and s[i + 1] == "_"
    and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] == "_"))
  ):
    j = i + 2
    while j < len(s) and s[j].isdigit():
      j += 1
    if j > i + 2 and j < len(s) and s[j] == "_":
      i = j + 1
      continue

  # Normalize temp variable names like `x_7` -> `x`.
  if (
    ch == "x"
    and i + 2 < len(s)
    and s[i + 1] == "_"
    and s[i + 2].isdigit()
    and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] == "_"))
  ):
    j = i + 2
    while j < len(s) and s[j].isdigit():
      j += 1
    if j > i + 2 and (j == len(s) or not (s[j].isalnum() or s[j] == "_")):
      out.append("x")
      i = j
      continue

  if ch.isspace():
    if out and out[-1] != " ":
      out.append(" ")
    i += 1
    continue

  out.append(ch)
  i += 1

normalized = "".join(out).strip()
normalized = sort_logica_type_segments(normalized)
normalized = drop_redundant_relation_aliases(normalized)
sys.stdout.write(normalized)
PY
}

if [[ ! -d "${UPSTREAM_ROOT}/.git" ]]; then
  rm -rf "${UPSTREAM_ROOT}"
  git clone --filter=blob:none "${UPSTREAM_REPO_URL}" "${UPSTREAM_ROOT}"
else
  git -C "${UPSTREAM_ROOT}" fetch --all --tags --prune
fi

git -C "${UPSTREAM_ROOT}" checkout --detach --force "${commit}"
resolved_commit="$(git -C "${UPSTREAM_ROOT}" rev-parse HEAD)"
echo "Upstream logica commit: ${resolved_commit}"

diff_path="${PARITY_TMP_ROOT}/python_parity.diff"

normalized_root="${PARITY_TMP_ROOT}/normalized"

while IFS=$'\t' read -r engine name src predicate import_root; do
  fixture_path="${FIXTURES_ROOT}/${src}"
  golden_path="${GOLDENS_ROOT}/${engine}/${name}.sql"
  out_path="${PYTHON_SQL_ROOT}/${engine}/${name}.sql"

  if [[ ! -f "${fixture_path}" ]]; then
    echo "Error: missing fixture: ${fixture_path}" >&2
    exit 1
  fi

  fixture_abs="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${fixture_path}")"

  if [[ ! -f "${golden_path}" ]]; then
    echo "Error: missing golden SQL: ${golden_path}" >&2
    exit 1
  fi

  declared_engine="$(
    ruby -e 'm = File.read(ARGV[0]).match(/@Engine\("([^"]+)"/); puts(m ? m[1] : "")' "${fixture_path}" || true
  )"
  if [[ -z "${declared_engine}" ]]; then
    echo "Error: fixture has no @Engine(...) declaration: ${src}" >&2
    exit 1
  fi
  if [[ "${declared_engine}" != "${engine}" ]]; then
    echo "Error: engine mismatch for ${src}: manifest=${engine}, fixture=@Engine(\"${declared_engine}\")" >&2
    exit 1
  fi

  if [[ -n "${import_root}" ]]; then
    logicapath="${FIXTURES_ROOT}/${import_root}"
  else
    logicapath="${FIXTURES_ROOT}"
  fi

  mkdir -p "$(dirname "${out_path}")"
  (cd "${UPSTREAM_ROOT}" && LOGICAPATH="${logicapath}" python3 logica.py "${fixture_abs}" print "${predicate}") > "${out_path}"

  golden_norm="${normalized_root}/golden/${engine}/${name}.sql"
  python_norm="${normalized_root}/python/${engine}/${name}.sql"
  mkdir -p "$(dirname "${golden_norm}")" "$(dirname "${python_norm}")"
  normalize_sql "${golden_path}" > "${golden_norm}"
  normalize_sql "${out_path}" > "${python_norm}"

  if ! diff -u "${golden_norm}" "${python_norm}" > "${diff_path}"; then
    echo "Python parity failed: ${engine}/${name} (${src} :: ${predicate})" >&2
    head -n 120 "${diff_path}" >&2
    echo "Golden: ${golden_path}" >&2
    echo "Python:  ${out_path}" >&2
    exit 1
  fi
done < <(
  ruby -ryaml -e '
    manifest = YAML.load_file(ARGV[0])
    tests = manifest.fetch("tests")

    %w[sqlite psql].each do |engine|
      tests.fetch(engine).each do |entry|
        name = entry.fetch("name")
        src = entry.fetch("src")
        predicate = entry["predicate"] || "Test"

        import_root = entry["import_root"]
        import_root = import_root.join(":") if import_root.is_a?(Array)

        puts [engine, name, src, predicate, import_root.to_s].join("\t")
      end
    end
  ' "${MANIFEST_PATH}"
)

echo "Python parity OK."
