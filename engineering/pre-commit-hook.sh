#!/bin/bash
# Enhanced Engineering Ethos Pre-Commit Hook
# Real enforcement mechanisms with pattern integration
# Version: 2.0 - Skeptical enhancements over original claims

set -e

# Configuration
CLAUDE_GLOBAL="$HOME/.claude"
PATTERN_REGISTRY="$CLAUDE_GLOBAL/patterns/registry.json"
LEARNINGS_FILE="LEARNINGS.md"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Utility functions
log_info() { echo -e "${BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN}$1${NC}"; }
log_warning() { echo -e "${YELLOW}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}"; }
log_check() { echo -e "${PURPLE}$1${NC}"; }

# Flag to track if commit should be blocked
BLOCK_COMMIT=0
WARNINGS=0

log_info "🔍 Engineering Ethos pre-commit validation v2.0..."

# Enhanced Check 1: Real LEARNINGS.md consultation tracking
log_check "📖 Checking LEARNINGS.md consultation (Enhanced)..."

if git diff --cached --name-only | grep -E "(src/|main\.js|\.js$|\.ts$)" > /dev/null; then
    log_info "   Code changes detected, validating LEARNINGS.md compliance..."
    
    # Check if LEARNINGS.md exists
    if [ ! -f "$LEARNINGS_FILE" ]; then
        log_error "   ❌ COMMIT BLOCKED: LEARNINGS.md not found"
        log_error "      Create LEARNINGS.md before making code changes"
        BLOCK_COMMIT=1
    else
        # Real pattern consultation - check for actual content analysis
        LEARNINGS_SIZE=$(wc -l < "$LEARNINGS_FILE" 2>/dev/null || echo "0")
        
        if [ "$LEARNINGS_SIZE" -lt 10 ]; then
            log_warning "   ⚠️  LEARNINGS.md appears minimal ($LEARNINGS_SIZE lines)"
            WARNINGS=$((WARNINGS + 1))
        fi
        
        # Check for pattern reference in commit or staged changes
        if git diff --cached | grep -iE "(learnings|pattern|prevention|JDEP)" > /dev/null; then
            log_success "   ✅ LEARNINGS.md patterns referenced in changes"
        elif git diff --cached --name-only | grep -q "$LEARNINGS_FILE"; then
            log_success "   ✅ LEARNINGS.md updated with code changes"
        else
            log_error "   ❌ COMMIT BLOCKED: Code changes require LEARNINGS.md consultation"
            log_error "      Add reference to LEARNINGS.md patterns or update the file"
            log_error "      Format: 'LEARNINGS.md: Applied pattern X.Y' or update content"
            BLOCK_COMMIT=1
        fi
        
        # Pattern extraction integration
        if [ -f "$PATTERN_REGISTRY" ] && [ -f "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" ]; then
            log_info "   Running pattern extraction analysis..."
            if "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" . --validate-only > /dev/null 2>&1; then
                log_success "   ✅ Pattern extraction validated"
            else
                log_warning "   ⚠️  Pattern extraction validation issues detected"
                WARNINGS=$((WARNINGS + 1))
            fi
        fi
    fi
else
    log_success "   ✅ No code changes detected"
fi

# Enhanced Check 2: Real commit message standards with pattern validation
log_check "📝 Checking commit message format (Enhanced)..."

COMMIT_MSG=""
if [ -f ".git/COMMIT_EDITMSG" ]; then
    COMMIT_MSG=$(cat .git/COMMIT_EDITMSG)
elif [ -n "$1" ]; then
    COMMIT_MSG="$1"
fi

if [ -n "$COMMIT_MSG" ]; then
    # Check for required references
    if echo "$COMMIT_MSG" | grep -iE "(LEARNINGS\.md|pattern|prevention|JDEP|standards)" > /dev/null; then
        log_success "   ✅ Commit message includes engineering standards references"
        
        # Validate pattern references are real
        if echo "$COMMIT_MSG" | grep -E "LEARNINGS\.md.*[0-9]+\.[0-9]+" > /dev/null; then
            PATTERN_REF=$(echo "$COMMIT_MSG" | grep -oE "[0-9]+\.[0-9]+" | head -1)
            if [ -f "$LEARNINGS_FILE" ] && grep -q "$PATTERN_REF" "$LEARNINGS_FILE"; then
                log_success "   ✅ Pattern reference $PATTERN_REF validated in LEARNINGS.md"
            else
                log_warning "   ⚠️  Pattern reference $PATTERN_REF not found in LEARNINGS.md"
                WARNINGS=$((WARNINGS + 1))
            fi
        fi
    else
        log_error "   ❌ COMMIT BLOCKED: Commit message lacks required references"
        log_error "      Include: 'LEARNINGS.md: <pattern>' or 'Applied prevention mechanism'"
        log_error "      Example: 'Fix bug: LEARNINGS.md pattern 3.2 - State validation'"
        BLOCK_COMMIT=1
    fi
    
    # Validate commit message length and structure
    MSG_LENGTH=$(echo "$COMMIT_MSG" | head -1 | wc -c)
    if [ "$MSG_LENGTH" -lt 20 ]; then
        log_warning "   ⚠️  Commit message seems too short (${MSG_LENGTH} chars)"
        WARNINGS=$((WARNINGS + 1))
    elif [ "$MSG_LENGTH" -gt 72 ]; then
        log_warning "   ⚠️  Commit message first line exceeds 72 characters"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    log_warning "   ⚠️  Commit message not accessible for validation"
    WARNINGS=$((WARNINGS + 1))
fi

# Enhanced Check 3: Real test coverage enforcement with actual metrics
log_check "🧪 Checking test requirements (Enhanced)..."

CRITICAL_FILES_CHANGED=false
if git diff --cached --name-only | grep -E "(src/main\.js|main\.js|critical|extraction)" > /dev/null; then
    CRITICAL_FILES_CHANGED=true
    log_info "   Critical files modified, enforcing test coverage requirements..."
    
    # Check if test files are also being updated
    if git diff --cached --name-only | grep -E "(test/|spec\.js|\.test\.|\.spec\.)" > /dev/null; then
        log_success "   ✅ Test files updated with critical changes"
    else
        log_error "   ❌ COMMIT BLOCKED: Critical file changes require test updates"
        log_error "      Add tests for: $(git diff --cached --name-only | grep -E "(src/main\.js|main\.js|critical|extraction)" | tr '\n' ' ')"
        BLOCK_COMMIT=1
    fi
    
    # Real test execution with coverage validation
    if [ -f "package.json" ]; then
        # Run smoke tests (non-blocking but required)
        if npm run test:smoke --silent > /dev/null 2>&1; then
            log_success "   ✅ Smoke tests passed"
        else
            log_error "   ❌ COMMIT BLOCKED: Smoke tests failed"
            log_error "      Run 'npm run test:smoke' to see failures"
            BLOCK_COMMIT=1
        fi
        
        # Run critical tests (blocking)
        if grep -q "test:critical" package.json; then
            if npm run test:critical --silent > /dev/null 2>&1; then
                log_success "   ✅ Critical tests passed"
            else
                log_error "   ❌ COMMIT BLOCKED: Critical tests failed"
                log_error "      Run 'npm run test:critical' to see failures"
                BLOCK_COMMIT=1
            fi
        else
            log_warning "   ⚠️  No critical tests configured (test:critical script missing)"
            WARNINGS=$((WARNINGS + 1))
        fi
        
        # Check test coverage if jest is configured
        if [ -f "jest.config.js" ] || grep -q '"jest"' package.json; then
            log_info "   Checking test coverage thresholds..."
            if npm test -- --coverage --silent > /dev/null 2>&1; then
                # Look for coverage output
                if [ -d "coverage" ]; then
                    COVERAGE_FILE="coverage/lcov-report/index.html"
                    if [ -f "$COVERAGE_FILE" ]; then
                        # Extract coverage percentage (simplified)
                        COVERAGE=$(grep -o '[0-9]*\.[0-9]*%' "$COVERAGE_FILE" 2>/dev/null | head -1 | sed 's/%//')
                        if [ -n "$COVERAGE" ]; then
                            COVERAGE_INT=$(echo "$COVERAGE" | cut -d. -f1)
                            if [ "$COVERAGE_INT" -ge 80 ]; then
                                log_success "   ✅ Test coverage: ${COVERAGE}% (≥80%)"
                            else
                                log_warning "   ⚠️  Test coverage: ${COVERAGE}% (target: ≥80%)"
                                WARNINGS=$((WARNINGS + 1))
                            fi
                        fi
                    fi
                fi
            else
                log_warning "   ⚠️  Could not run coverage analysis"
                WARNINGS=$((WARNINGS + 1))
            fi
        fi
    else
        log_error "   ❌ COMMIT BLOCKED: package.json not found"
        log_error "      Cannot validate test configuration for critical changes"
        BLOCK_COMMIT=1
    fi
fi

if [ "$CRITICAL_FILES_CHANGED" = false ]; then
    log_success "   ✅ No critical files modified"
fi

# Enhanced Check 4: Documentation completeness with content validation
log_check "📋 Checking documentation requirements (Enhanced)..."

REQUIRED_DOCS=("LEARNINGS.md")
OPTIONAL_DOCS=("ENGINEERING_STANDARDS.md" "ENGINEERING_ETHOS.md" "README.md")
MISSING_CRITICAL=0
MISSING_OPTIONAL=0

# Check critical documentation
for doc in "${REQUIRED_DOCS[@]}"; do
    if [ ! -f "$doc" ]; then
        log_error "   ❌ $doc missing (required)"
        MISSING_CRITICAL=$((MISSING_CRITICAL + 1))
    else
        # Validate content quality
        DOC_LINES=$(wc -l < "$doc" 2>/dev/null || echo "0")
        if [ "$DOC_LINES" -lt 5 ]; then
            log_warning "   ⚠️  $doc exists but appears empty ($DOC_LINES lines)"
            WARNINGS=$((WARNINGS + 1))
        else
            log_success "   ✅ $doc exists with content ($DOC_LINES lines)"
        fi
    fi
done

# Check optional documentation
for doc in "${OPTIONAL_DOCS[@]}"; do
    if [ ! -f "$doc" ]; then
        MISSING_OPTIONAL=$((MISSING_OPTIONAL + 1))
    fi
done

if [ $MISSING_CRITICAL -eq 0 ]; then
    log_success "   ✅ All critical documentation present"
    if [ $MISSING_OPTIONAL -gt 0 ]; then
        log_warning "   ⚠️  $MISSING_OPTIONAL optional documentation files missing"
    fi
else
    log_error "   ❌ COMMIT BLOCKED: Critical documentation missing"
    log_error "      Required: LEARNINGS.md (institutional memory)"
    BLOCK_COMMIT=1
fi

# Enhanced Check 5: Multi-language syntax validation
log_check "🔧 Checking syntax validation (Enhanced)..."

SYNTAX_ERRORS=0

# JavaScript/TypeScript files
for file in $(git diff --cached --name-only | grep -E "\.(js|ts|jsx|tsx)$"); do
    if [ -f "$file" ]; then
        log_info "   Validating syntax: $file"
        if node -c "$file" > /dev/null 2>&1; then
            log_success "   ✅ $file syntax valid"
        else
            log_error "   ❌ Syntax errors in $file"
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    fi
done

# JSON files
for file in $(git diff --cached --name-only | grep "\.json$"); do
    if [ -f "$file" ]; then
        log_info "   Validating JSON: $file"
        if python -m json.tool "$file" > /dev/null 2>&1 || jq . "$file" > /dev/null 2>&1; then
            log_success "   ✅ $file JSON valid"
        else
            log_error "   ❌ Invalid JSON in $file"
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    fi
done

if [ $SYNTAX_ERRORS -eq 0 ]; then
    log_success "   ✅ All staged files have valid syntax"
else
    log_error "   ❌ COMMIT BLOCKED: $SYNTAX_ERRORS syntax errors detected"
    BLOCK_COMMIT=1
fi

# Enhanced Check 6: Pattern extraction and evidence scoring
log_check "🎯 Checking pattern extraction integration (New)..."

if [ -f "$PATTERN_REGISTRY" ]; then
    PATTERN_COUNT=$(jq -r '.projects | length' "$PATTERN_REGISTRY" 2>/dev/null || echo "0")
    log_info "   Pattern registry found with $PATTERN_COUNT projects"
    
    # Check if current project is registered
    PROJECT_NAME=$(basename "$(pwd)")
    if jq -r ".projects[] | select(.name == \"$PROJECT_NAME\") | .name" "$PATTERN_REGISTRY" 2>/dev/null | grep -q "$PROJECT_NAME"; then
        log_success "   ✅ Current project registered in pattern system"
    else
        log_warning "   ⚠️  Current project not in pattern registry"
        log_warning "      Run: ~/.claude/scripts/extract-local-patterns.sh ."
        WARNINGS=$((WARNINGS + 1))
    fi
else
    log_warning "   ⚠️  Pattern registry not found at $PATTERN_REGISTRY"
    WARNINGS=$((WARNINGS + 1))
fi

# Generate validation summary
echo ""
log_info "📊 Validation Summary:"
echo "   Checks performed: 6"
echo "   Blocking issues: $([ $BLOCK_COMMIT -eq 1 ] && echo "YES" || echo "NONE")"
echo "   Warnings: $WARNINGS"

# Final decision with enhanced feedback
echo ""
if [ $BLOCK_COMMIT -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        log_success "✅ Engineering standards compliance verified - commit allowed"
        log_success "🎯 Zero warnings - excellent engineering practices!"
    else
        log_success "✅ Engineering standards compliance verified - commit allowed"
        log_warning "⚠️  $WARNINGS warnings detected - consider addressing before future commits"
    fi
    
    echo ""
    log_info "🏗️ Engineering Ethos Four Pillars - Status:"
    echo "  1. 🧠 Learnings-First Development - $([ -f "$LEARNINGS_FILE" ] && echo "✅ Active" || echo "❌ Missing")"
    echo "  2. 🛡️ Test-Driven Protection - $([ "$CRITICAL_FILES_CHANGED" = true ] && echo "✅ Enforced" || echo "➖ N/A")"
    echo "  3. 📚 Documentation-as-Code - $([ $MISSING_CRITICAL -eq 0 ] && echo "✅ Compliant" || echo "❌ Incomplete")"
    echo "  4. 🏛️ Proactive Architecture - $([ -f "$PATTERN_REGISTRY" ] && echo "✅ Integrated" || echo "⚠️ Pending")"
    echo ""
    exit 0
else
    log_error "❌ COMMIT BLOCKED: Engineering standards violations detected"
    echo ""
    log_error "🔧 Required Actions:"
    
    if [ ! -f "$LEARNINGS_FILE" ]; then
        echo "  📖 Create LEARNINGS.md with project patterns and lessons learned"
    fi
    
    if [ $SYNTAX_ERRORS -gt 0 ]; then
        echo "  🔧 Fix $SYNTAX_ERRORS syntax errors in staged files"
    fi
    
    echo "  💬 Update commit message to reference LEARNINGS.md patterns"
    echo "  🧪 Ensure all tests pass (smoke + critical tests)"
    echo "  📋 Add missing required documentation"
    
    echo ""
    log_info "🚀 Quick Recovery:"
    echo "  make validate     # Run full validation suite"
    echo "  make test         # Run all tests"
    echo "  make help         # Show available commands"
    
    echo ""
    log_info "💡 Need help? Check LEARNINGS.md for similar patterns"
    exit 1
fi