#!/bin/bash
# shell-integration.sh - Shell integration for Claude Code pattern extraction system

# Installation function
install_shell_integration() {
    local shell_config=""
    
    # Detect shell and config file
    if [[ "$SHELL" == */zsh ]]; then
        shell_config="$HOME/.zshrc"
    elif [[ "$SHELL" == */bash ]]; then
        shell_config="$HOME/.bashrc"
    else
        echo "⚠️ Unsupported shell: $SHELL"
        echo "Please manually add integration to your shell config"
        return 1
    fi
    
    echo "🔧 Installing Claude Code shell integration..."
    echo "📁 Target config: $shell_config"
    
    # Create backup
    cp "$shell_config" "$shell_config.claude.backup.$(date +%Y%m%d_%H%M%S)"
    echo "💾 Backup created: $shell_config.claude.backup.*"
    
    # Add integration code
    cat >> "$shell_config" << 'EOF'

# ============================================================================
# Claude Code Pattern Extraction System Integration
# ============================================================================

# Claude Code project detection and context loading
claude_project_context() {
    if [[ -f "CLAUDE.md" || -f "LEARNINGS.md" ]]; then
        # Set project context flag
        export CLAUDE_PROJECT="$(basename "$(pwd)")"
        
        # Load context quietly (show only key info)
        local context_output=$(~/.claude/scripts/session-context.sh load 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            # Extract evidence score from context
            local evidence=$(echo "$context_output" | grep "Evidence score:" | cut -d: -f2 | xargs || echo "0")
            export CLAUDE_EVIDENCE="$evidence"
            
            # Show brief context info
            echo "🧬 Claude Code context loaded for $CLAUDE_PROJECT (evidence: $evidence)"
            
            # Show applicable patterns from other projects
            local pattern_count=$(find ~/.claude/patterns/validated -name "*.json" 2>/dev/null | wc -l)
            if [[ $pattern_count -gt 0 ]]; then
                echo "💡 $pattern_count validated patterns available from other projects"
            fi
        fi
    else
        unset CLAUDE_PROJECT CLAUDE_EVIDENCE
    fi
}

# Auto-trigger context loading on directory change
claude_enhanced_cd() {
    builtin cd "$@"
    local exit_code=$?
    
    # Only run context loading if cd was successful
    if [[ $exit_code -eq 0 ]]; then
        claude_project_context
    fi
    
    return $exit_code
}

# Replace cd command with enhanced version
alias cd='claude_enhanced_cd'

# Show Claude status in prompt
claude_prompt_status() {
    if [[ -n "$CLAUDE_PROJECT" && -n "$CLAUDE_EVIDENCE" ]]; then
        local color=""
        local status=""
        
        # Color based on evidence score
        if (( $(echo "$CLAUDE_EVIDENCE > 0.8" | bc -l 2>/dev/null || echo 0) )); then
            color="\033[92m"  # Green
            status="⚡"
        elif (( $(echo "$CLAUDE_EVIDENCE > 0.7" | bc -l 2>/dev/null || echo 0) )); then
            color="\033[93m"  # Yellow  
            status="🎯"
        elif (( $(echo "$CLAUDE_EVIDENCE > 0.5" | bc -l 2>/dev/null || echo 0) )); then
            color="\033[94m"  # Blue
            status="🔧"
        else
            color="\033[90m"  # Gray
            status="📝"
        fi
        
        echo -e "${color}${status}${CLAUDE_PROJECT}(${CLAUDE_EVIDENCE})\033[0m"
    fi
}

# Enhanced prompt with Claude status (only if prompt customization is wanted)
# Uncomment to enable:
# PS1='$(claude_prompt_status) '$PS1

# Useful aliases for Claude Code evolution
alias claude-status='~/.claude/scripts/evolution-report.sh dashboard'
alias claude-patterns='find ~/.claude/patterns/pending -name "*.json" -exec jq -r ".project + \": \" + (.evidence_score | tostring)" {} \; 2>/dev/null'
alias claude-weekly='~/.claude/scripts/evolution-report.sh weekly'
alias claude-extract='~/.claude/scripts/extract-local-patterns.sh $(pwd)'
alias claude-save='~/.claude/scripts/session-context.sh save'
alias claude-load='~/.claude/scripts/session-context.sh load'

# Auto-save context when exiting shell (optional)
# Uncomment to enable:
# trap 'if [[ -n "$CLAUDE_PROJECT" ]]; then ~/.claude/scripts/session-context.sh save 2>/dev/null; fi' EXIT

echo "✅ Claude Code shell integration loaded"
echo "💡 Use 'claude-status' to see evolution dashboard"

# ============================================================================
# End Claude Code Integration
# ============================================================================
EOF
    
    echo ""
    echo "✅ Shell integration installed successfully!"
    echo ""
    echo "🚀 Next steps:"
    echo "  1. Restart your shell or run: source $shell_config"
    echo "  2. Navigate to a Claude Code project to test integration"
    echo "  3. Use 'claude-status' to view evolution dashboard"
    echo ""
    echo "📋 Available commands:"
    echo "  claude-status     # Evolution dashboard"
    echo "  claude-patterns   # List pattern candidates"
    echo "  claude-weekly     # Generate weekly report"
    echo "  claude-extract    # Extract patterns from current project"
    echo "  claude-save       # Save current session context"
    echo "  claude-load       # Load project context"
}

# Uninstall function
uninstall_shell_integration() {
    local shell_config=""
    
    if [[ "$SHELL" == */zsh ]]; then
        shell_config="$HOME/.zshrc"
    elif [[ "$SHELL" == */bash ]]; then
        shell_config="$HOME/.bashrc"
    else
        echo "⚠️ Please manually remove Claude Code integration from your shell config"
        return 1
    fi
    
    echo "🔧 Removing Claude Code shell integration..."
    
    # Create backup
    cp "$shell_config" "$shell_config.pre-removal.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remove integration section
    sed '/# Claude Code Pattern Extraction System Integration/,/# End Claude Code Integration/d' "$shell_config" > "$shell_config.tmp"
    mv "$shell_config.tmp" "$shell_config"
    
    echo "✅ Shell integration removed"
    echo "💾 Backup created: $shell_config.pre-removal.backup.*"
    echo "🔄 Please restart your shell to complete removal"
}

# Git hooks installation
install_git_hooks() {
    echo "🔧 Installing global Git hooks for pattern extraction..."
    
    # Configure git to use global hooks
    git config --global core.hooksPath ~/.claude/git-hooks
    
    # Create hooks directory
    mkdir -p ~/.claude/git-hooks
    
    # Create post-commit hook
    cat > ~/.claude/git-hooks/post-commit << 'EOF'
#!/bin/bash
# Global post-commit hook for Claude Code pattern extraction

COMMIT_MSG=$(git log -1 --pretty=%B)

# Check if this commit contains JDEP methodology
if echo "$COMMIT_MSG" | grep -q "JDEP\|Root Cause\|Pattern\|Phase"; then
    echo "🎯 JDEP methodology detected - extracting patterns..."
    
    # Run pattern extraction in background to avoid blocking commit
    (
        ~/.claude/scripts/extract-local-patterns.sh "$(pwd)" > /dev/null 2>&1
        echo "✅ Pattern extraction completed"
    ) &
fi
EOF
    
    chmod +x ~/.claude/git-hooks/post-commit
    
    echo "✅ Git hooks installed"
    echo "💡 Patterns will be extracted automatically after JDEP commits"
}

# Test integration
test_integration() {
    echo "🧪 Testing Claude Code integration..."
    
    # Test scripts exist and are executable
    local scripts=(
        "$HOME/.claude/scripts/extract-local-patterns.sh"
        "$HOME/.claude/scripts/session-context.sh"
        "$HOME/.claude/scripts/evolution-report.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -x "$script" ]]; then
            echo "✅ $script is executable"
        else
            echo "❌ $script is missing or not executable"
            return 1
        fi
    done
    
    # Test pattern registry
    if [[ -f ~/.claude/patterns/registry.json ]]; then
        echo "✅ Pattern registry exists"
    else
        echo "❌ Pattern registry missing"
        return 1
    fi
    
    # Test evolution dashboard
    echo ""
    echo "🎯 Testing evolution dashboard:"
    ~/.claude/scripts/evolution-report.sh dashboard | head -5
    
    echo ""
    echo "✅ Integration test passed!"
}

# Main command handler
case "${1:-install}" in
    "install")
        install_shell_integration
        install_git_hooks
        test_integration
        ;;
    "uninstall")
        uninstall_shell_integration
        ;;
    "git-hooks")
        install_git_hooks
        ;;
    "test")
        test_integration
        ;;
    *)
        echo "Usage: $0 {install|uninstall|git-hooks|test}"
        echo ""
        echo "Commands:"
        echo "  install      # Install complete shell integration"
        echo "  uninstall    # Remove shell integration" 
        echo "  git-hooks    # Install only Git hooks"
        echo "  test         # Test integration components"
        exit 1
        ;;
esac