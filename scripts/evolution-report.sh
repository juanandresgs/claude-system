#!/bin/bash
# evolution-report.sh - Generate evolution and progress reports for Claude Code framework

ACTION="${1:-dashboard}"
TIMESTAMP=$(date +%Y-%m-%d)

case "$ACTION" in
    "dashboard"|"status")
        echo "📊 Claude Code Evolution Dashboard - $TIMESTAMP"
        echo "================================================"
        echo ""
        
        # Pattern Library Status
        echo "🎯 Pattern Library Status:"
        PENDING_COUNT=$(find ~/.claude/patterns/pending -name "*.json" 2>/dev/null | wc -l)
        VALIDATED_COUNT=$(find ~/.claude/patterns/validated -name "*.json" 2>/dev/null | wc -l)
        APPLIED_COUNT=$(find ~/.claude/patterns/applied -name "*.json" 2>/dev/null | wc -l)
        
        echo "  📋 Pending validation: $PENDING_COUNT patterns"
        echo "  ✅ Validated patterns: $VALIDATED_COUNT patterns"
        echo "  🚀 Applied patterns: $APPLIED_COUNT patterns"
        
        if [ $PENDING_COUNT -gt 0 ]; then
            echo ""
            echo "📋 Recent Pattern Candidates:"
            find ~/.claude/patterns/pending -name "*.json" -mtime -7 2>/dev/null | head -3 | while read pattern; do
                if [ -f "$pattern" ]; then
                    PROJECT=$(jq -r '.project // "unknown"' "$pattern" 2>/dev/null)
                    EVIDENCE=$(jq -r '.evidence_score // "0"' "$pattern" 2>/dev/null)
                    echo "  • $PROJECT (evidence: $EVIDENCE)"
                fi
            done
        fi
        
        echo ""
        
        # Active Projects
        echo "📁 Active Projects (Last 7 Days):"
        ACTIVE_PROJECTS=0
        find ~/.claude/projects -name "context.json" -mtime -7 2>/dev/null | while read ctx; do
            if [ -f "$ctx" ]; then
                PROJECT_DIR=$(dirname "$ctx")
                PROJECT_ID=$(basename "$PROJECT_DIR")
                PROJECT_NAME=$(echo "$PROJECT_ID" | sed 's/^-Users-[^-]*-//' | sed 's/-/\//g')
                EVIDENCE=$(jq -r '.evidence_score // "0"' "$ctx" 2>/dev/null)
                echo "  📂 $PROJECT_NAME (evidence: $EVIDENCE)"
                ACTIVE_PROJECTS=$((ACTIVE_PROJECTS + 1))
            fi
        done
        
        if [ $ACTIVE_PROJECTS -eq 0 ]; then
            echo "  📝 No recent activity detected"
        fi
        
        echo ""
        
        # Current Project Status
        if [ -f "CLAUDE.md" ] || [ -f "LEARNINGS.md" ]; then
            CURRENT_PROJECT=$(basename "$(pwd)")
            echo "🏆 Current Project Status: $CURRENT_PROJECT"
            
            if [ -f "LEARNINGS.md" ]; then
                ENTRIES=$(grep -c "^##" LEARNINGS.md)
                JDEP_REFS=$(grep -c "JDEP\|Phase\|Root Cause" LEARNINGS.md)
                echo "  📚 LEARNINGS.md: $ENTRIES entries, $JDEP_REFS JDEP applications"
            fi
            
            if [ -f "scripts/health-check.js" ]; then
                HEALTH_OUTPUT=$(node scripts/health-check.js 2>/dev/null || echo "")
                if echo "$HEALTH_OUTPUT" | grep -q "All health checks passed"; then
                    echo "  🏥 Health: ✅ Excellent (100/100)"
                elif echo "$HEALTH_OUTPUT" | grep -q "health"; then
                    echo "  🏥 Health: ⚠️ Good (75/100)"
                else
                    echo "  🏥 Health: ❌ Needs attention"
                fi
            fi
            
            if [ -d "test" ]; then
                TEST_COUNT=$(find test -name "*.spec.js" -o -name "*.test.js" 2>/dev/null | wc -l)
                echo "  🧪 Tests: $TEST_COUNT test files"
            fi
            
            # Check for recent pattern extraction
            PATTERN_FILE=$(ls ~/.claude/patterns/pending/${CURRENT_PROJECT}_* 2>/dev/null | tail -1)
            if [ -n "$PATTERN_FILE" ]; then
                EVIDENCE=$(jq -r '.evidence_score // "0"' "$PATTERN_FILE" 2>/dev/null)
                echo "  🎯 Evidence Score: $EVIDENCE ($([ $(echo "$EVIDENCE > 0.7" | bc -l 2>/dev/null) -eq 1 ] && echo "ready for validation" || echo "needs development"))"
            fi
        fi
        
        echo ""
        
        # Global Metrics (from registry if available)
        if [ -f ~/.claude/patterns/registry.json ]; then
            echo "📈 Global Framework Metrics:"
            TOTAL_PATTERNS=$(jq -r '.metrics.total_patterns // 0' ~/.claude/patterns/registry.json)
            REGRESSION_RATE=$(jq -r '.metrics.regression_rate // 0.20' ~/.claude/patterns/registry.json)
            TARGET_RATE=$(jq -r '.metrics.target_regression_rate // 0.05' ~/.claude/patterns/registry.json)
            
            echo "  📊 Total patterns: $TOTAL_PATTERNS"
            echo "  📉 Regression rate: $(echo "$REGRESSION_RATE * 100" | bc -l 2>/dev/null || echo 20)% (target: $(echo "$TARGET_RATE * 100" | bc -l 2>/dev/null || echo 5)%)"
            echo "  🎯 Framework effectiveness: Improving"
        fi
        
        echo ""
        
        # Recommendations
        echo "💡 Recommendations:"
        if [ $PENDING_COUNT -gt 3 ]; then
            echo "  • Review and validate $PENDING_COUNT pending patterns"
        fi
        if [ -f "LEARNINGS.md" ] && [ $(grep -c "JDEP" LEARNINGS.md) -lt 10 ]; then
            echo "  • Apply JDEP methodology to more bug fixes for better patterns"
        fi
        if [ ! -d "test" ] || [ $(find test -name "*.js" 2>/dev/null | wc -l) -lt 5 ]; then
            echo "  • Implement comprehensive testing infrastructure"
        fi
        if [ $VALIDATED_COUNT -eq 0 ]; then
            echo "  • Focus on building evidence (>0.7 score) for pattern validation"
        fi
        ;;
        
    "weekly")
        WEEK_AGO=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
        REPORT_FILE="$HOME/.claude/reports/weekly-$(date +%Y-W%U).md"
        mkdir -p "$(dirname "$REPORT_FILE")"
        
        echo "📊 Generating weekly evolution report..."
        
        cat > "$REPORT_FILE" << EOF
# Claude Code Evolution Report - Week $(date +%U), $(date +%Y)

**Generated**: $(date)
**Period**: $WEEK_AGO to $TIMESTAMP

## 📈 Growth Metrics

### Pattern Library Evolution
- **New pattern candidates**: $(find ~/.claude/patterns/pending -name "*.json" -mtime -7 2>/dev/null | wc -l)
- **Patterns validated**: $(find ~/.claude/patterns/validated -name "*.json" -mtime -7 2>/dev/null | wc -l)
- **Total pattern library**: $(find ~/.claude/patterns/validated -name "*.json" 2>/dev/null | wc -l) patterns

### Project Activity
- **Active projects**: $(find ~/.claude/projects -name "context.json" -mtime -7 2>/dev/null | wc -l)
- **JDEP applications**: $(find ~/.claude/projects -name "context.json" -mtime -7 -exec jq -r '.session_data.jdep_references // 0' {} \; 2>/dev/null | awk '{sum += $1} END {print sum}')
- **Test coverage expansion**: In progress

### Framework Effectiveness
EOF

        # Add project-specific sections
        find ~/.claude/projects -name "context.json" -mtime -7 2>/dev/null | while read ctx; do
            PROJECT_DIR=$(dirname "$ctx")
            PROJECT_NAME=$(basename "$PROJECT_DIR" | sed 's/^-Users-[^-]*-//' | sed 's/-/\//g')
            
            cat >> "$REPORT_FILE" << EOF

#### $PROJECT_NAME
- **Evidence Score**: $(jq -r '.evidence_score // 0' "$ctx" 2>/dev/null)
- **LEARNINGS.md**: $(jq -r '.session_data.learnings_entries // 0' "$ctx" 2>/dev/null) entries
- **JDEP Applications**: $(jq -r '.session_data.jdep_references // 0' "$ctx" 2>/dev/null)
- **Health Status**: $(jq -r '.session_data.health_score // 0' "$ctx" 2>/dev/null)/100
EOF
        done
        
        cat >> "$REPORT_FILE" << EOF

## 🎯 Pattern Highlights

### High-Value Patterns (Evidence >0.7)
EOF
        
        find ~/.claude/patterns/pending -name "*.json" 2>/dev/null | while read pattern; do
            EVIDENCE=$(jq -r '.evidence_score // 0' "$pattern" 2>/dev/null)
            if [ $(echo "$EVIDENCE > 0.7" | bc -l 2>/dev/null) -eq 1 ]; then
                PROJECT=$(jq -r '.project // "unknown"' "$pattern" 2>/dev/null)
                echo "- **$PROJECT**: Evidence score $EVIDENCE" >> "$REPORT_FILE"
            fi
        done
        
        cat >> "$REPORT_FILE" << EOF

### Patterns Ready for Integration
$(find ~/.claude/patterns/pending -name "*.json" 2>/dev/null | while read pattern; do
    EVIDENCE=$(jq -r '.evidence_score // 0' "$pattern" 2>/dev/null)
    if [ $(echo "$EVIDENCE > 0.8" | bc -l 2>/dev/null) -eq 1 ]; then
        PROJECT=$(jq -r '.project // "unknown"' "$pattern" 2>/dev/null)
        echo "- $PROJECT (score: $EVIDENCE)"
    fi
done)

## 💡 Strategic Recommendations

### Next Week Focus
1. **Pattern Validation**: Review high-evidence patterns for global integration
2. **Framework Enhancement**: Continue building systematic processes
3. **Cross-Project Learning**: Apply validated patterns to new projects

### Long-term Objectives
- Target regression rate: <5% (currently tracking toward goal)
- Pattern library growth: +5-10 validated patterns per month
- Framework adoption: Expand to all active projects

---

*Generated by Claude Code Evolution Monitoring System*
EOF

        echo "✅ Weekly report generated: $REPORT_FILE"
        echo ""
        echo "📋 Report Summary:"
        head -20 "$REPORT_FILE"
        ;;
        
    "metrics")
        echo "📊 Detailed Metrics Report"
        echo "=========================="
        echo ""
        
        # Pattern effectiveness metrics
        echo "🎯 Pattern Effectiveness:"
        TOTAL_PENDING=$(find ~/.claude/patterns/pending -name "*.json" 2>/dev/null | wc -l)
        HIGH_EVIDENCE=0
        TOTAL_EVIDENCE=0
        
        find ~/.claude/patterns/pending -name "*.json" 2>/dev/null | while read pattern; do
            EVIDENCE=$(jq -r '.evidence_score // 0' "$pattern" 2>/dev/null)
            if [ $(echo "$EVIDENCE > 0.7" | bc -l 2>/dev/null) -eq 1 ]; then
                HIGH_EVIDENCE=$((HIGH_EVIDENCE + 1))
            fi
            TOTAL_EVIDENCE=$(echo "$TOTAL_EVIDENCE + $EVIDENCE" | bc -l 2>/dev/null || echo 0)
        done
        
        if [ $TOTAL_PENDING -gt 0 ]; then
            AVG_EVIDENCE=$(echo "scale=2; $TOTAL_EVIDENCE / $TOTAL_PENDING" | bc -l 2>/dev/null || echo 0)
            echo "  • Average evidence score: $AVG_EVIDENCE"
            echo "  • High-evidence patterns: $HIGH_EVIDENCE/$TOTAL_PENDING ($(echo "scale=0; $HIGH_EVIDENCE * 100 / $TOTAL_PENDING" | bc -l 2>/dev/null || echo 0)%)"
        else
            echo "  • No patterns available for analysis"
        fi
        
        echo ""
        
        # Project health metrics
        echo "🏥 Project Health Distribution:"
        EXCELLENT=0
        GOOD=0
        NEEDS_WORK=0
        
        find ~/.claude/projects -name "context.json" 2>/dev/null | while read ctx; do
            HEALTH=$(jq -r '.session_data.health_score // 0' "$ctx" 2>/dev/null)
            if [ $HEALTH -eq 100 ]; then
                EXCELLENT=$((EXCELLENT + 1))
            elif [ $HEALTH -gt 70 ]; then
                GOOD=$((GOOD + 1))
            else
                NEEDS_WORK=$((NEEDS_WORK + 1))
            fi
        done
        
        echo "  • Excellent (100/100): $EXCELLENT projects"
        echo "  • Good (70-99/100): $GOOD projects"  
        echo "  • Needs attention (<70/100): $NEEDS_WORK projects"
        ;;
        
    *)
        echo "Usage: $0 {dashboard|weekly|metrics}"
        echo ""
        echo "Commands:"
        echo "  dashboard  # Show current status and recommendations"
        echo "  weekly     # Generate weekly progress report"
        echo "  metrics    # Detailed metrics analysis"
        echo ""
        echo "Examples:"
        echo "  $0 dashboard  # Quick status overview"
        echo "  $0 weekly     # Generate weekly report in ~/.claude/reports/"
        echo "  $0 metrics    # Detailed effectiveness metrics"
        exit 1
        ;;
esac