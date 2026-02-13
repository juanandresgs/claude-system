# Content Snapshot Template — v0.2

**Origin:** PodcastPrep TTS Dashboard, Feb 2026
**Purpose:** Structured, verifiable representation of source material with verbatim quotes, structural transparency, and labeled editorial.

## Design Principles

1. **Source text is sacred** — quotes are verbatim, never paraphrased
2. **Interpretation is labeled** — reader always knows source vs. analyst
3. **Traceability** — every claim has page/section reference
4. **Completeness over brevity** — include enough quotes to cover all substantive content; the user decides what to skip, not the tool

## Template Sections (in order)

### 1. Key Findings (Author Summary)
- Verbatim bullets from the report's own summary/executive summary
- Include page references
- No commentary
- If no author summary exists, note: "No author summary present" and skip

### 2. Document Structure (Full Report Map)
- Chapter/section outline with 1-2 sentence neutral descriptions
- Include page ranges (for PDFs) or section anchors (for web)

### 3. Coverage Map (What's Included vs. Omitted)
- Table: Section | Covered? | Evidence (quote count) | Notes
- If omitted, list why (e.g., repetitive, background only, no novel findings)
- Must account for every section listed in the Document Structure

### 4. Selected Content (Verbatim, Tagged)
Selection criteria note at top.
For each covered section:
- Section heading + pages/location
- Relevance tag (2-3 words)
- 1-3 short verbatim quotes (prefer 1-3 sentences each) + page/section refs
- Each quote in `<blockquote>` with `<cite>` for reference
- Optional: visual/figure description if present

### 5. Why This Matters — According to the Authors
- Direct quotes from conclusion/implications/recommendations
- No paraphrase

### 6. Analyst Assessment (Clearly Editorial)
- Opens with italic disclaimer: *"The following is editorial analysis, not source material."*
- Brief synthesis (max 250 words)
- Distinguish inference vs. report content
- No new facts not grounded in the source

### 7. Representation Assessment
- 4-6 bullet evaluation of how representative this snapshot is of the full source
- Note bias or gaps (topic, geography, policy, perspective, etc.)
- Note the source's own perspective/bias

## Output Rules
- Remove UI artifacts, file paths, pagination chrome from quotes
- No invented data or paraphrased quotes
- Every blockquote must include a `<cite>` with page/section reference
- No text outside blockquotes presents itself as source material
