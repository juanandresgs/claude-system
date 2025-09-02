# Pattern Extraction and Evolution System

**Version**: 1.0.0  
**Integration**: Autonomous Framework Evolution System (AFES)  
**Purpose**: Continuous pattern extraction and global CLAUDE.md enhancement

---

## Automatic Pattern Extraction Protocol

### Session Lifecycle Integration

#### Session Start
```bash
# When entering a project directory
if [[ -f "CLAUDE.md" || -f "LEARNINGS.md" ]]; then
    ~/.claude/scripts/session-context.sh load
    ~/.claude/scripts/evolution-report.sh dashboard
fi
```

#### During Development
- JDEP methodology applications tracked automatically
- Pattern detection runs via git hooks
- Evidence accumulation monitored continuously

#### Session End
```bash
# When leaving project or ending session
~/.claude/scripts/session-context.sh save
~/.claude/scripts/extract-local-patterns.sh $(pwd)
```

### Pattern Validation Workflow

#### Automatic Validation (Evidence Score ≥0.8)
```yaml
criteria:
  jdep_applications: ">30 documented applications"
  pattern_documentation: ">5 explicit patterns identified"
  testing_infrastructure: ">10 test files"
  commit_evidence: ">5 JDEP-methodology commits"
  knowledge_base_size: ">25,000 tokens"

action: "Auto-integrate to global pattern library"
notification: "Pattern validated and ready for cross-project application"
```

#### Manual Review Required (Evidence Score 0.7-0.8)
```yaml
criteria:
  moderate_evidence: "Strong in some areas, needs development in others"
  
action: "Queue for review and enhancement"
workflow: "Continue local development until evidence threshold met"
```

#### Local Development (Evidence Score <0.7)
```yaml
criteria:
  insufficient_evidence: "Needs more JDEP applications and testing"
  
action: "Continue building local patterns and evidence"
focus: "JDEP methodology, testing infrastructure, pattern documentation"
```

---

## Cross-Project Pattern Application

### Context Loading for New Projects
```bash
# When starting work on any project
PROJECT_TYPE=$(detect_project_type)
APPLICABLE_PATTERNS=$(find_applicable_patterns $PROJECT_TYPE)

if [[ ${#APPLICABLE_PATTERNS[@]} -gt 0 ]]; then
    echo "💡 Applicable patterns from other projects:"
    for pattern in "${APPLICABLE_PATTERNS[@]}"; do
        echo "  🔗 $(get_pattern_description $pattern)"
    done
fi
```

### Pattern Suggestion System
```yaml
triggers:
  - bug_fix_started: "Suggest JDEP methodology and similar pattern solutions"
  - test_writing: "Suggest multi-tier testing patterns (P0/P1/P2)"
  - refactoring: "Suggest validated refactoring patterns from other projects"
  - performance_issues: "Suggest performance optimization patterns"

delivery:
  - context_aware: "Show patterns relevant to current task"
  - evidence_based: "Only suggest patterns with >0.7 validation score"
  - actionable: "Include specific implementation guidance"
```

---

## Global Framework Evolution

### Registry Updates
```bash
# Automatic registry maintenance
update_global_registry() {
    local project="$1"
    local evidence_score="$2"
    local patterns_count="$3"
    
    jq --arg project "$project" \
       --arg timestamp "$(date -Iseconds)" \
       --argjson evidence "$evidence_score" \
       --argjson patterns "$patterns_count" \
       '.projects[$project].last_analyzed = $timestamp |
        .projects[$project].evidence_score = $evidence |
        .projects[$project].patterns_extracted = $patterns |
        .last_updated = $timestamp' \
       ~/.claude/patterns/registry.json > ~/.claude/patterns/registry.json.tmp &&
    mv ~/.claude/patterns/registry.json.tmp ~/.claude/patterns/registry.json
}
```

### Evolution Notifications
```bash
# Desktop notifications for framework evolution
notify_pattern_validated() {
    local pattern="$1"
    local score="$2"
    osascript -e "display notification \"Pattern validated: $pattern (score: $score)\" with title \"Claude Evolution\" subtitle \"Ready for cross-project use\""
}

notify_framework_update() {
    local patterns_count="$1"
    osascript -e "display notification \"$patterns_count new patterns available\" with title \"Claude Framework Updated\" subtitle \"Enhanced global knowledge\""
}
```

---

## Shell Integration

### Automatic Project Context
```bash
# Add to ~/.zshrc or ~/.bashrc

# Claude Code project detection and context loading
claude_project_context() {
    if [[ -f "CLAUDE.md" || -f "LEARNINGS.md" ]]; then
        # Load project context
        ~/.claude/scripts/session-context.sh load 2>/dev/null | tail -5
        
        # Show evolution status in prompt
        export CLAUDE_CONTEXT="🧬$(~/.claude/scripts/evolution-report.sh dashboard | grep "Evidence Score" | cut -d: -f2 | xargs)"
    else
        unset CLAUDE_CONTEXT
    fi
}

# Auto-trigger on directory change
cd() {
    builtin cd "$@" && claude_project_context
}

# Show Claude evolution status in prompt
claude_status() {
    if [[ -n "$CLAUDE_CONTEXT" ]]; then
        echo "$CLAUDE_CONTEXT"
    fi
}

# Enhanced prompt with Claude status
PS1='$(claude_status) '$PS1
```

### Git Hooks Integration
```bash
# Global git hooks for pattern extraction
git config --global core.hooksPath ~/.claude/git-hooks

# Create global post-commit hook
mkdir -p ~/.claude/git-hooks
cat > ~/.claude/git-hooks/post-commit << 'EOF'
#!/bin/bash
# Extract patterns after JDEP methodology commits

COMMIT_MSG=$(git log -1 --pretty=%B)

if echo "$COMMIT_MSG" | grep -q "JDEP\|Root Cause\|Pattern\|Phase"; then
    echo "🎯 JDEP methodology detected - extracting patterns..."
    ~/.claude/scripts/extract-local-patterns.sh "$(pwd)" &
fi
EOF

chmod +x ~/.claude/git-hooks/post-commit
```

---

## Success Metrics and Monitoring

### Continuous Tracking
```yaml
daily_metrics:
  patterns_extracted: "Track new pattern candidates"
  evidence_scores: "Monitor pattern quality improvement"
  cross_project_applications: "Count pattern reuse"
  regression_rate: "Track bug prevention effectiveness"

weekly_reports:
  evolution_summary: "~/.claude/scripts/evolution-report.sh weekly"
  pattern_validation: "Review high-evidence patterns"
  framework_effectiveness: "Measure compound learning impact"

monthly_analysis:
  global_regression_rate: "Measure framework effectiveness"
  pattern_library_growth: "Track knowledge accumulation"
  cross_project_learning: "Measure pattern reuse success"
```

### Dashboard Access
```bash
# Quick commands for monitoring evolution
alias claude-status='~/.claude/scripts/evolution-report.sh dashboard'
alias claude-patterns='find ~/.claude/patterns/pending -name "*.json" -exec jq -r ".project + \": \" + (.evidence_score | tostring)" {} \;'
alias claude-weekly='~/.claude/scripts/evolution-report.sh weekly'
```

---

## Implementation Status

### ✅ Currently Working
1. **Pattern Extraction**: Extract patterns from projects with evidence scoring
2. **Registry Management**: Track projects and pattern evolution
3. **Evolution Reporting**: Dashboard and weekly reports functional
4. **Session Context**: Save/load project context across sessions

### 🚧 In Development
1. **Cross-Project Pattern Suggestions**: Show applicable patterns from other projects
2. **Automatic Validation**: Validate patterns and integrate to global library
3. **Shell Integration**: Seamless project switching with context

### 🎯 Future Enhancements
1. **ML Pattern Recognition**: Automated pattern extraction from conversations
2. **Predictive Analytics**: Suggest patterns before issues occur
3. **Community Sharing**: Share validated patterns across teams
4. **IDE Integration**: Native editor support for pattern application

---

## Getting Started

### Immediate Setup (5 minutes)
```bash
# 1. Add to your shell profile (~/.zshrc or ~/.bashrc)
echo 'source ~/.claude/PATTERN_EXTRACTION.md' >> ~/.zshrc

# 2. Test pattern extraction on current project
~/.claude/scripts/extract-local-patterns.sh $(pwd)

# 3. View evolution dashboard
~/.claude/scripts/evolution-report.sh dashboard
```

### Weekly Routine
```bash
# Generate weekly report
~/.claude/scripts/evolution-report.sh weekly

# Review high-evidence patterns for validation
find ~/.claude/patterns/pending -name "*.json" -exec jq 'select(.evidence_score > 0.7)' {} \;

# Apply validated patterns to new projects
claude-status  # Check for applicable patterns
```

---

*This pattern extraction system enables continuous evolution of the global CLAUDE.md framework through systematic extraction, validation, and application of engineering patterns across all projects.*