# llm-wiki-colab

Ontology, SHACL shapes, and SPARQL pipeline for **`llm-wiki-colab`**: a
multi-agent, federated extension of the
[llm-wiki](https://github.com/tobi/llm-wiki) memory pattern with a typed-edge
vocabulary and contribution / reconciliation primitives.

Serves the IRI namespace at <https://la3d.github.io/llm-wiki-colab/> and ships
the wiki → JSON-LD → Turtle build with materialized inverses and Jena-based
SPARQL queries.

## Why a new namespace

The `llm-wiki` pattern (Tobi Lütke / Shopify) is widely associated with that
name. This project extends it with multi-agent attribution, cross-project
contribution / reconciliation, and a richer typed-edge vocabulary, so it
deserves a distinct prefix and IRI base to avoid collision.

- Prefix: `llm-wiki-colab:`
- IRI base: `https://la3d.github.io/llm-wiki-colab/`
  - Ontology terms: `<.../ontology#>`
  - Page IRIs: `<.../page/{Page-Name}>`

The IRI base is a GitHub Pages URL on a repo we control. Dereferenceable
ontology documentation can be published there later; for now the IRIs are
stable identifiers that resolve to a real repo.

## Typed-edge vocabulary

Forward predicates the author asserts (in frontmatter or via inline body-link
annotation) and the inverses the build pipeline materializes:

| Forward | Inverse | Use |
|---|---|---|
| `up` | — | hierarchy parent (every page has one) |
| `source` | — | cites this external literature item |
| `extends` | — | builds on the intellectual content of the target |
| `supports` | `supportedBy` | provides evidence FOR the target's claim |
| `criticizes` | `criticizedBy` | argues against the target's claim |
| `concept` | `conceptOf` | discusses the target concept |
| `partOf` | `hasPart` | structural component or stage of the target |
| `dependsOn` | `prerequisiteOf` | design / argument depends on the target |
| `defines` | `definedBy` | canonical definition source for the target |
| `resolvedBy` | `resolves` | open question here is answered by the target |
| `incorporatedInto` | `incorporates` | content appears in the target (staging pattern) |
| `outOfScopeFor` | `excludes` | content explicitly NOT to appear in the target |
| `precedes` | `precededBy` | sequence order (version, stage, phase) |
| `feedsInto` | `informedBy` | signal / data flow into a pipeline |
| `related` | — | fallback when nothing more specific fits |
| `mentions` | — | body cross-reference, emitted automatically by the extractor |

Inline body-link annotation form (Variant 1, agent-readable + self-documenting):

```markdown
[Concept-X](Concept-X) ([*supports*](Edge-Types#supports))
```

The plain content link emits a `mentions` edge; the predicate link adds the
typed edge. Predicate-carrier links to `Edge-Types#*` are excluded from
`mentions` to keep that page from becoming a spurious hub.

## Pipeline

```
wiki/*.md                     ← author-edited Markdown with YAML frontmatter
   │
   ▼   wiki-to-jsonld.py      ← extracts frontmatter + body-link annotations
*-graph.jsonld
   │
   ▼   riot (Apache Jena)     ← JSON-LD → Turtle
*-graph.ttl  +  *-weights.ttl ← weighted mentions as RDF-star
   │
   ▼   arq CONSTRUCT queries  ← materialize area inheritance + inverse edges + hubs
*-graph-full.ttl
   │
   ▼   shacl validate         ← *-shapes.ttl
validation-report.ttl
```

Built artifacts (`*-graph*.ttl`, `*-graph.jsonld`, `validation-report.ttl`)
are generated, not checked in.

## Quick start

Requires:
- Python 3
- Apache Jena CLI (`riot`, `arq`, `shacl`) — `brew install jena`

Build the KG from a wiki:

```bash
./build-graph.sh --wiki=/path/to/your.wiki --stats
```

Run a canned SPARQL query against the built graph:

```bash
arq --data=graph-full.ttl --query=sparql/hub-notes.rq
```

## Layout

```
ontology.ttl       OWL/SKOS ontology (classes + predicates)
context.jsonld     JSON-LD context (prefix + edge term mappings)
shapes.ttl         SHACL shapes (frontmatter validation)
queries.ttl        Example queries in Turtle form (reference)
build-graph.sh     End-to-end pipeline
wiki-to-jsonld.py  Frontmatter + body-link extractor
sparql/            18 canned SPARQL queries (.rq)
```

File names are unqualified (no `llm-wiki-colab-` prefix) because the
repo itself carries the namespace: when these files are dereferenced via
GitHub Pages they land at `https://la3d.github.io/llm-wiki-colab/ontology.ttl`
etc., matching the IRI base structure.

## Attribution

The KG pipeline is adapted from the working ontology and tooling in Charles
Vardeman's `agentic-vault`, with additions for the multi-agent / federated
case (extra typed-edge predicates including `partOf`, `dependsOn`, `defines`,
`resolvedBy`, `incorporatedInto`, `outOfScopeFor`, `precedes`, `feedsInto`,
and their inverses; the visible body-link annotation form;
contribution-status-aware verifier rules).
