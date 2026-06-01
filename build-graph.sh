#!/bin/bash
# build-graph.sh — Full pipeline: vault notes → JSON-LD → Turtle → materialize → validate
# Usage: ./build-graph.sh --wiki=PATH [--stats] [--skip-validate] [--skip-materialize]
#
# Outputs (written next to this script):
#   llm-wiki-colab-graph.jsonld      (intermediate JSON-LD)
#   llm-wiki-colab-graph.ttl         (base Turtle graph)
#   llm-wiki-colab-graph-full.ttl    (base + materialized triples)
#   validation-report.ttl            (SHACL validation report)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"
JSONLD_OUT="$SCRIPT_DIR/llm-wiki-colab-graph.jsonld"
TURTLE_OUT="$SCRIPT_DIR/llm-wiki-colab-graph.ttl"
WEIGHTS_OUT="$SCRIPT_DIR/llm-wiki-colab-graph-weights.ttl"
FULL_OUT="$SCRIPT_DIR/llm-wiki-colab-graph-full.ttl"
SHAPES="$SCRIPT_DIR/llm-wiki-colab-shapes.ttl"
REPORT_OUT="$SCRIPT_DIR/validation-report.ttl"

STATS_FLAG=""
SKIP_VALIDATE=""
SKIP_MATERIALIZE=""
WIKI_PATH=""
for arg in "$@"; do
    case "$arg" in
        --stats) STATS_FLAG="--stats" ;;
        --skip-validate) SKIP_VALIDATE=1 ;;
        --skip-materialize) SKIP_MATERIALIZE=1 ;;
        --wiki=*) WIKI_PATH="${arg#--wiki=}" ;;
    esac
done

# Determine source mode: --wiki=PATH uses wiki mode, otherwise vault mode
if [[ -n "$WIKI_PATH" ]]; then
    SOURCE_FLAG="--wiki"
    SOURCE_PATH="$(cd "$WIKI_PATH" && pwd)"
    echo "=== Wiki Knowledge Graph Build ===" >&2
    echo "Wiki: $SOURCE_PATH" >&2
else
    SOURCE_FLAG="--vault"
    SOURCE_PATH="$VAULT_ROOT"
    echo "=== Vault Knowledge Graph Build ===" >&2
    echo "Vault: $SOURCE_PATH" >&2
fi
echo "" >&2

# Step 1: Extract frontmatter + body links → JSON-LD + weighted mentions
echo "Step 1: Extracting frontmatter → JSON-LD..." >&2
python3 "$SCRIPT_DIR/wiki-to-jsonld.py" \
    $SOURCE_FLAG "$SOURCE_PATH" \
    --output "$JSONLD_OUT" \
    $STATS_FLAG

echo "" >&2

# Step 2: Convert JSON-LD → Turtle via riot
echo "Step 2: Converting JSON-LD → Turtle via riot..." >&2
riot --syntax=jsonld --output=turtle "$JSONLD_OUT" 2>/dev/null > "$TURTLE_OUT"

# Merge weighted mentions if the weights file was generated
if [[ -f "$WEIGHTS_OUT" ]]; then
    echo "" >> "$TURTLE_OUT"
    echo "# --- Weighted mentions (RDF-star) ---" >> "$TURTLE_OUT"
    cat "$WEIGHTS_OUT" >> "$TURTLE_OUT"
    echo "Merged weighted mentions from $WEIGHTS_OUT" >&2
fi

echo "Turtle written to $TURTLE_OUT" >&2
echo "Lines in Turtle: $(wc -l < "$TURTLE_OUT" | tr -d ' ')" >&2
echo "" >&2

# Step 3: Materialize implied triples via CONSTRUCT queries
# Each query outputs N-Triples (no prefix conflicts when concatenating)
if [[ -z "$SKIP_MATERIALIZE" ]]; then
    echo "Step 3: Materializing implied triples..." >&2
    INFERRED=$(mktemp)

    run_construct() {
        arq --data="$TURTLE_OUT" --query=<(echo "$1") 2>/dev/null | \
            riot --syntax=turtle --output=ntriples 2>/dev/null >> "$INFERRED"
    }

    # Area inheritance: propagate area down up: hierarchy
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?note llm-wiki-colab:area ?area }
WHERE {
    ?note llm-wiki-colab:up+ ?ancestor .
    ?ancestor llm-wiki-colab:area ?area .
    FILTER NOT EXISTS { ?note llm-wiki-colab:area ?area }
}'

    # Inverse supports
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:supportedBy ?source }
WHERE { ?source llm-wiki-colab:supports ?target }'

    # Inverse criticizes
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:criticizedBy ?source }
WHERE { ?source llm-wiki-colab:criticizes ?target }'

    # Inverse concept
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:conceptOf ?source }
WHERE { ?source llm-wiki-colab:concept ?target }'

    # Inverse partOf (llm-wiki addition)
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:hasPart ?source }
WHERE { ?source llm-wiki-colab:partOf ?target }'

    # Inverse dependsOn (llm-wiki addition)
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:prerequisiteOf ?source }
WHERE { ?source llm-wiki-colab:dependsOn ?target }'

    # Inverse defines (llm-wiki addition)
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:definedBy ?source }
WHERE { ?source llm-wiki-colab:defines ?target }'

    # Inverse resolvedBy (llm-wiki addition)
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:resolves ?source }
WHERE { ?source llm-wiki-colab:resolvedBy ?target }'

    # Inverse incorporatedInto (llm-wiki addition)
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:incorporates ?source }
WHERE { ?source llm-wiki-colab:incorporatedInto ?target }'

    # Inverse outOfScopeFor (llm-wiki addition)
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:excludes ?source }
WHERE { ?source llm-wiki-colab:outOfScopeFor ?target }'

    # Inverse precedes (llm-wiki addition)
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:precededBy ?source }
WHERE { ?source llm-wiki-colab:precedes ?target }'

    # Inverse feedsInto (llm-wiki addition)
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?target llm-wiki-colab:informedBy ?source }
WHERE { ?source llm-wiki-colab:feedsInto ?target }'

    # Hub detection
    run_construct 'PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
CONSTRUCT { ?note llm-wiki-colab:isHub true }
WHERE {
    { SELECT ?note (COUNT(?src) AS ?inbound) WHERE {
        ?src ?pred ?note .
        FILTER(?pred IN (llm-wiki-colab:up, llm-wiki-colab:area, llm-wiki-colab:concept, llm-wiki-colab:source,
                         llm-wiki-colab:extends, llm-wiki-colab:supports, llm-wiki-colab:criticizes,
                         llm-wiki-colab:implementation, llm-wiki-colab:related))
    } GROUP BY ?note }
    FILTER(?inbound >= 10)
}'

    INFERRED_COUNT=$(wc -l < "$INFERRED" | tr -d ' ')
    echo "Materialized ~${INFERRED_COUNT} triples" >&2

    # Merge: convert inferred N-Triples to Turtle, then concatenate
    # arq can load multiple --data files, so we keep them separate for querying
    # For the combined file, append N-Triples after the base Turtle
    # (N-Triples are valid at the end of a Turtle file since Turtle is a superset)
    cp "$TURTLE_OUT" "$FULL_OUT"
    echo "" >> "$FULL_OUT"
    echo "# --- Materialized triples ---" >> "$FULL_OUT"
    cat "$INFERRED" >> "$FULL_OUT"
    rm "$INFERRED"

    echo "Full graph written to $FULL_OUT" >&2
    echo "Lines in full graph: $(wc -l < "$FULL_OUT" | tr -d ' ')" >&2
    echo "" >&2
fi

# Step 4: SHACL validation
if [[ -z "$SKIP_VALIDATE" ]]; then
    echo "Step 4: SHACL validation..." >&2
    VALIDATE_DATA="${FULL_OUT}"
    [[ -n "$SKIP_MATERIALIZE" ]] && VALIDATE_DATA="$TURTLE_OUT"

    shacl validate --shapes="$SHAPES" --data="$VALIDATE_DATA" > "$REPORT_OUT" 2>&1

    # Summary
    VIOLATIONS=$(grep -c "sh:Violation" "$REPORT_OUT" || true)
    WARNINGS=$(grep -c "sh:Warning" "$REPORT_OUT" || true)
    INFOS=$(grep -c "sh:Info" "$REPORT_OUT" || true)
    echo "Validation report: $REPORT_OUT" >&2
    if grep -q "sh:conforms  true" "$REPORT_OUT"; then
        echo "Result: CONFORMS" >&2
    else
        echo "Result: ${VIOLATIONS} violations, ${WARNINGS} warnings, ${INFOS} info" >&2
    fi
    echo "" >&2
fi

# Step 5: Quick stats query
echo "Step 5: Type distribution..." >&2
QUERY_DATA="${FULL_OUT}"
[[ -n "$SKIP_MATERIALIZE" ]] && QUERY_DATA="$TURTLE_OUT"

arq --data="$QUERY_DATA" --query=<(cat <<'SPARQL'
PREFIX llm-wiki-colab: <https://la3d.github.io/llm-wiki-colab/ontology#>
SELECT ?type (COUNT(?note) AS ?count) WHERE {
    ?note a ?type .
} GROUP BY ?type ORDER BY DESC(?count)
SPARQL
) 2>&1

echo "" >&2
echo "=== Done ===" >&2
