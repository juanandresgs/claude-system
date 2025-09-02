#!/bin/bash
# session-context.sh - Preserve and restore project context across Claude Code sessions

PROJECT=$(basename "$(pwd)")
PROJECT_PATH=$(pwd)
ACTION="${1:-save}"
TIMESTAMP=$(date -Iseconds)

# Create project-specific directory if it doesn't exist
PROJECT_DIR="$HOME/.claude/projects/$(echo "$PROJECT_PATH" | sed 's|/|-|g')"
mkdir -p "$PROJECT_DIR"

if [ "$ACTION" = "save" ]; then
    echo "💾 Saving context for $PROJECT..."
    
    # Gather project metrics
    LEARNINGS_SIZE=0
    LEARNINGS_ENTRIES=0
    JDEP_REFERENCES=0
    if [ -f "LEARNINGS.md" ]; then
        LEARNINGS_SIZE=$(wc -l LEARNINGS.md | awk '{print $1}')
        LEARNINGS_ENTRIES=$(grep -c "^##" LEARNINGS.md)
        JDEP_REFERENCES=$(grep -c "JDEP\|Phase\|Root Cause" LEARNINGS.md)
    fi
    
    # Count test files
    TEST_COUNT=0
    if [ -d "test" ]; then
        TEST_COUNT=$(find test -name "*.spec.js" -o -name "*.test.js" 2>/dev/null | wc -l)
    fi
    
    # Pattern detection results
    PATTERNS_DETECTED=0
    PATTERN_WARNINGS=0
    if [ -f "scripts/pattern-checker.js" ]; then
        PATTERN_OUTPUT=$(node scripts/pattern-checker.js 2>&1 || echo "")
        PATTERNS_DETECTED=$(echo "$PATTERN_OUTPUT" | grep -c "Pattern detected" || echo 0)
        PATTERN_WARNINGS=$(echo "$PATTERN_OUTPUT" | grep -c "warning" || echo 0)
    fi
    
    # Health check score
    HEALTH_SCORE=0
    if [ -f "scripts/health-check.js" ]; then
        HEALTH_OUTPUT=$(node scripts/health-check.js 2>&1 || echo "")
        if echo "$HEALTH_OUTPUT" | grep -q "All health checks passed"; then
            HEALTH_SCORE=100
        elif echo "$HEALTH_OUTPUT" | grep -q "health checks"; then
            HEALTH_SCORE=75
        fi
    fi
    
    # Git activity (commits in last week)
    RECENT_COMMITS=0
    if [ -d ".git" ]; then
        RECENT_COMMITS=$(git log --since="7 days ago" --oneline 2>/dev/null | wc -l)
    fi
    
    # Calculate session productivity score
    PRODUCTIVITY_SCORE=$(node -e "
    const learnings = $LEARNINGS_ENTRIES;
    const jdep = $JDEP_REFERENCES;
    const tests = $TEST_COUNT;
    const health = $HEALTH_SCORE;
    const commits = $RECENT_COMMITS;
    
    let score = 0;
    if (learnings > 50) score += 0.2;
    if (jdep > 30) score += 0.3;
    if (tests > 10) score += 0.2;
    if (health === 100) score += 0.2;
    if (commits > 5) score += 0.1;
    
    console.log(Math.round(Math.min(score * 100, 100)));
    ")
    
    # Get last pattern extraction
    LAST_PATTERN=$(ls ~/.claude/patterns/pending/${PROJECT}_* 2>/dev/null | tail -1)
    EVIDENCE_SCORE_VAL=$([ -n "$LAST_PATTERN" ] && jq -r .evidence_score "$LAST_PATTERN" 2>/dev/null || echo "0")
    
    # Create JSON using jq for proper formatting
    jq -n \
        --arg project "$PROJECT" \
        --arg path "$PROJECT_PATH" \
        --arg timestamp "$TIMESTAMP" \
        --argjson learnings_size "$LEARNINGS_SIZE" \
        --argjson learnings_entries "$LEARNINGS_ENTRIES" \
        --argjson jdep_references "$JDEP_REFERENCES" \
        --argjson test_count "$TEST_COUNT" \
        --argjson patterns_detected "$PATTERNS_DETECTED" \
        --argjson pattern_warnings "$PATTERN_WARNINGS" \
        --argjson health_score "$HEALTH_SCORE" \
        --argjson recent_commits "$RECENT_COMMITS" \
        --argjson productivity_score "$PRODUCTIVITY_SCORE" \
        --arg has_claude_md "$([ -f "CLAUDE.md" ] && echo "true" || echo "false")" \
        --arg has_learnings "$([ -f "LEARNINGS.md" ] && echo "true" || echo "false")" \
        --arg has_testing "$([ -d "test" ] && echo "true" || echo "false")" \
        --arg has_automation "$([ -d "scripts" ] && echo "true" || echo "false")" \
        --arg has_ci_cd "$([ -d ".github/workflows" ] && echo "true" || echo "false")" \
        --arg last_patterns_extracted "${LAST_PATTERN:-null}" \
        --argjson evidence_score "$EVIDENCE_SCORE_VAL" \
        '{
            "project": $project,
            "path": $path,
            "timestamp": $timestamp,
            "session_data": {
                "learnings_size": $learnings_size,
                "learnings_entries": $learnings_entries,
                "jdep_references": $jdep_references,
                "test_count": $test_count,
                "patterns_detected": $patterns_detected,
                "pattern_warnings": $pattern_warnings,
                "health_score": $health_score,
                "recent_commits": $recent_commits,
                "productivity_score": $productivity_score
            },
            "framework_status": {
                "has_claude_md": ($has_claude_md == "true"),
                "has_learnings": ($has_learnings == "true"),
                "has_testing": ($has_testing == "true"),
                "has_automation": ($has_automation == "true"),
                "has_ci_cd": ($has_ci_cd == "true")
            },
            "last_patterns_extracted": (if $last_patterns_extracted == "null" then null else $last_patterns_extracted end),
            "evidence_score": $evidence_score
        }' > "$PROJECT_DIR/context.json"
    
    # Create session summary
    echo "📊 Session Summary:"
    echo "  📚 LEARNINGS.md: $LEARNINGS_ENTRIES entries ($JDEP_REFERENCES JDEP refs)"
    echo "  🧪 Tests: $TEST_COUNT test files"
    echo "  🏥 Health: $HEALTH_SCORE/100"
    echo "  📈 Productivity: ${PRODUCTIVITY_SCORE}/100"
    echo "  🎯 Evidence Score: $EVIDENCE_SCORE_VAL"
    echo ""
    echo "💾 Context saved to: $PROJECT_DIR/context.json"

elif [ "$ACTION" = "load" ]; then
    echo "📂 Loading context for $PROJECT..."
    
    CONTEXT_FILE="$PROJECT_DIR/context.json"
    if [ -f "$CONTEXT_FILE" ]; then
        echo ""
        echo "📊 Project Context:"
        echo "════════════════════"
        
        # Parse and display context
        LAST_SESSION=$(jq -r '.timestamp' "$CONTEXT_FILE")
        LEARNINGS_ENTRIES=$(jq -r '.session_data.learnings_entries' "$CONTEXT_FILE")
        JDEP_REFS=$(jq -r '.session_data.jdep_references' "$CONTEXT_FILE")
        HEALTH_SCORE=$(jq -r '.session_data.health_score' "$CONTEXT_FILE")
        PRODUCTIVITY=$(jq -r '.session_data.productivity_score' "$CONTEXT_FILE")
        EVIDENCE_SCORE=$(jq -r '.evidence_score' "$CONTEXT_FILE")
        
        echo "📅 Last session: $LAST_SESSION"
        echo "📚 Knowledge base: $LEARNINGS_ENTRIES entries, $JDEP_REFS JDEP applications"
        echo "🏥 Health score: $HEALTH_SCORE/100"
        echo "📈 Productivity: $PRODUCTIVITY/100"
        echo "🎯 Evidence score: $EVIDENCE_SCORE"
        
        # Show framework status
        echo ""
        echo "🛠️ Framework Status:"
        jq -r '.framework_status | to_entries[] | select(.value == true) | "  ✅ \(.key | gsub("has_"; "") | gsub("_"; " "))"' "$CONTEXT_FILE"
        jq -r '.framework_status | to_entries[] | select(.value == false) | "  ❌ \(.key | gsub("has_"; "") | gsub("_"; " "))"' "$CONTEXT_FILE"
        
        # Show applicable patterns from other projects
        echo ""
        echo "💡 Applicable Patterns from Other Projects:"
        PATTERN_COUNT=0
        find ~/.claude/patterns/validated -name "*.json" 2>/dev/null | head -3 | while read pattern; do
            if [ -f "$pattern" ]; then
                PATTERN_PROJECT=$(jq -r '.project // "unknown"' "$pattern" 2>/dev/null)
                PATTERN_TYPE=$(jq -r '.type // "general"' "$pattern" 2>/dev/null)
                echo "  🔗 $PATTERN_TYPE pattern from $PATTERN_PROJECT project"
                PATTERN_COUNT=$((PATTERN_COUNT + 1))
            fi
        done
        
        if [ $PATTERN_COUNT -eq 0 ]; then
            echo "  📝 No validated patterns available yet"
            echo "  💡 Focus on building patterns in this project first"
        fi
        
        echo ""
        echo "🚀 Ready to continue development!"
        
    else
        echo "ℹ️ No previous context found for $PROJECT"
        echo "💡 Starting fresh session - context will be saved automatically"
    fi

elif [ "$ACTION" = "status" ]; then
    # Quick status check
    if [ -f "$PROJECT_DIR/context.json" ]; then
        LAST_SESSION=$(jq -r '.timestamp' "$PROJECT_DIR/context.json" 2>/dev/null || echo "unknown")
        EVIDENCE_SCORE=$(jq -r '.evidence_score' "$PROJECT_DIR/context.json" 2>/dev/null || echo "0")
        echo "📊 $PROJECT: Last session $LAST_SESSION, Evidence: $EVIDENCE_SCORE"
    else
        echo "📊 $PROJECT: No context available"
    fi

else
    echo "Usage: $0 {save|load|status}"
    echo ""
    echo "Examples:"
    echo "  $0 save    # Save current project context"
    echo "  $0 load    # Load project context and show applicable patterns"  
    echo "  $0 status  # Quick status check"
    exit 1
fi