#!/bin/bash
# extract-local-patterns.sh - Extract patterns from local projects to global registry

PROJECT_PATH="${1:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_PATH")
TIMESTAMP=$(date -Iseconds)

echo "🔍 Extracting patterns from $PROJECT_NAME..."
echo "📍 Project path: $PROJECT_PATH"

# Check if this is a Claude Code project
if [ ! -f "$PROJECT_PATH/CLAUDE.md" ] && [ ! -f "$PROJECT_PATH/LEARNINGS.md" ]; then
    echo "ℹ️ No Claude Code framework files found. Skipping extraction."
    exit 0
fi

# Extract pattern data from LEARNINGS.md
LEARNINGS_FILE="$PROJECT_PATH/LEARNINGS.md"
if [ -f "$LEARNINGS_FILE" ]; then
    # Count JDEP methodology applications
    JDEP_COUNT=$(grep -c "JDEP\|Phase [0-6]\|Root Cause" "$LEARNINGS_FILE")
    PATTERN_COUNT=$(grep -c "Pattern Identified\|Prevention Strategy" "$LEARNINGS_FILE")
    LEARNINGS_SIZE=$(wc -c < "$LEARNINGS_FILE")
    ENTRY_COUNT=$(grep -c "^##" "$LEARNINGS_FILE")
    
    echo "📊 Found $JDEP_COUNT JDEP references"
    echo "📊 Found $PATTERN_COUNT documented patterns"
    echo "📊 Found $ENTRY_COUNT knowledge entries"
    echo "📊 LEARNINGS.md size: $LEARNINGS_SIZE bytes"
else
    JDEP_COUNT=0
    PATTERN_COUNT=0
    LEARNINGS_SIZE=0
    ENTRY_COUNT=0
fi

# Check for testing infrastructure
TEST_COUNT=0
if [ -d "$PROJECT_PATH/test" ]; then
    TEST_COUNT=$(find "$PROJECT_PATH/test" -name "*.spec.js" -o -name "*.test.js" 2>/dev/null | wc -l)
fi

# Check for automation scripts
SCRIPT_COUNT=0
if [ -d "$PROJECT_PATH/scripts" ]; then
    SCRIPT_COUNT=$(find "$PROJECT_PATH/scripts" -name "*.js" -o -name "*.sh" 2>/dev/null | wc -l)
fi

# Get git commit count with JDEP methodology
JDEP_COMMITS=0
if [ -d "$PROJECT_PATH/.git" ]; then
    cd "$PROJECT_PATH"
    JDEP_COMMITS=$(git log --oneline --grep="JDEP\|Root Cause\|Phase" 2>/dev/null | wc -l)
    cd - > /dev/null
fi

# Calculate evidence score (0.0-1.0)
EVIDENCE_SCORE=$(node -e "
const jdep = $JDEP_COUNT;
const patterns = $PATTERN_COUNT;
const commits = $JDEP_COMMITS;
const size = $LEARNINGS_SIZE;
const tests = $TEST_COUNT;
const scripts = $SCRIPT_COUNT;

// Scoring algorithm (max 1.0)
let score = 0;
if (jdep > 0) score += 0.3;          // JDEP usage
if (patterns > 0) score += 0.2;      // Documented patterns  
if (commits > 0) score += 0.2;       // JDEP commits
if (size > 5000) score += 0.1;       // Substantial documentation
if (tests > 0) score += 0.1;         // Testing infrastructure
if (scripts > 0) score += 0.1;       // Automation scripts

console.log(Math.min(score, 1.0).toFixed(2));
")

echo "📊 Evidence score: $EVIDENCE_SCORE"

# Create pattern extraction record
EXTRACTION_ID="${PROJECT_NAME}_$(date +%Y%m%d_%H%M%S)"
EXTRACTION_FILE="$HOME/.claude/patterns/pending/$EXTRACTION_ID.json"

cat > "$EXTRACTION_FILE" << EOF
{
  "id": "$EXTRACTION_ID",
  "project": "$PROJECT_NAME",
  "path": "$PROJECT_PATH",
  "extraction_date": "$TIMESTAMP",
  "evidence_score": $EVIDENCE_SCORE,
  "metrics": {
    "jdep_count": $JDEP_COUNT,
    "pattern_count": $PATTERN_COUNT,
    "entry_count": $ENTRY_COUNT,
    "learnings_size": $LEARNINGS_SIZE,
    "test_count": $TEST_COUNT,
    "script_count": $SCRIPT_COUNT,
    "jdep_commits": $JDEP_COMMITS
  },
  "status": "pending_validation",
  "validation_required": $([ $(echo "$EVIDENCE_SCORE >= 0.7" | bc -l) -eq 1 ] && echo "false" || echo "true"),
  "auto_integrate": $([ $(echo "$EVIDENCE_SCORE >= 0.8" | bc -l) -eq 1 ] && echo "true" || echo "false")
}
EOF

echo "✅ Pattern extraction completed"
echo "📁 Extraction record: $EXTRACTION_FILE"

# Update project registry
REGISTRY_FILE="$HOME/.claude/patterns/registry.json"
if [ -f "$REGISTRY_FILE" ]; then
    # Update registry with new project data
    jq --arg project "$PROJECT_NAME" \
       --arg path "$PROJECT_PATH" \
       --arg timestamp "$TIMESTAMP" \
       --argjson patterns "$PATTERN_COUNT" \
       --argjson learnings "$LEARNINGS_SIZE" \
       --argjson jdep "$JDEP_COUNT" \
       '.projects[$project] = {
         "path": $path,
         "last_analyzed": $timestamp,
         "patterns_extracted": $patterns,
         "learnings_size": $learnings,
         "jdep_applications": $jdep
       } | .last_updated = $timestamp' \
       "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" && mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    
    echo "📈 Updated project registry"
fi

# Provide recommendations based on evidence score
if [ $(echo "$EVIDENCE_SCORE >= 0.8" | bc -l) -eq 1 ]; then
    echo "🚀 High evidence score! Patterns ready for automatic integration."
elif [ $(echo "$EVIDENCE_SCORE >= 0.7" | bc -l) -eq 1 ]; then
    echo "✅ Good evidence score. Patterns ready for validation."
elif [ $(echo "$EVIDENCE_SCORE >= 0.5" | bc -l) -eq 1 ]; then
    echo "⚠️ Moderate evidence. Continue developing patterns locally."
else
    echo "📝 Low evidence score. Focus on JDEP documentation and testing."
fi

echo ""
echo "💡 To improve evidence score:"
if [ $JDEP_COUNT -eq 0 ]; then
    echo "  - Apply JDEP methodology to document bug fixes"
fi
if [ $PATTERN_COUNT -eq 0 ]; then
    echo "  - Document prevention strategies in LEARNINGS.md"
fi
if [ $TEST_COUNT -eq 0 ]; then
    echo "  - Add automated testing infrastructure"
fi
if [ $SCRIPT_COUNT -eq 0 ]; then
    echo "  - Create automation scripts for quality gates"
fi