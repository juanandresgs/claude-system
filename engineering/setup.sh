#!/bin/bash
# Engineering Ethos Global Setup Script
# Deploy engineering standards to any project from ~/.claude/engineering

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global paths
CLAUDE_GLOBAL="${HOME}/.claude"
ENGINEERING_GLOBAL="${CLAUDE_GLOBAL}/engineering"
PROJECT_PATH="${1:-$(pwd)}"
PROJECT_NAME="$(basename "$PROJECT_PATH")"

echo -e "${BLUE}🚀 Deploying Engineering Ethos to: $PROJECT_NAME${NC}"
echo -e "${BLUE}   Project path: $PROJECT_PATH${NC}"
echo -e "${BLUE}   Global config: $ENGINEERING_GLOBAL${NC}"
echo ""

# Validate global engineering framework exists
if [ ! -d "$ENGINEERING_GLOBAL" ]; then
    echo -e "${RED}❌ Global engineering framework not found at: $ENGINEERING_GLOBAL${NC}"
    echo "   Please ensure ~/.claude/engineering/ exists with the framework files"
    exit 1
fi

# Change to project directory
cd "$PROJECT_PATH" || {
    echo -e "${RED}❌ Cannot access project directory: $PROJECT_PATH${NC}"
    exit 1
}

# Step 1: Validate prerequisites
echo -e "${BLUE}📋 Validating prerequisites...${NC}"
command -v node >/dev/null 2>&1 || { 
    echo -e "${RED}❌ Node.js required but not found${NC}"
    echo "   Install Node.js: https://nodejs.org/"
    exit 1
}
echo -e "${GREEN}   ✅ Node.js found: $(node --version)${NC}"

command -v git >/dev/null 2>&1 || { 
    echo -e "${RED}❌ Git required but not found${NC}"
    exit 1
}
echo -e "${GREEN}   ✅ Git found: $(git --version)${NC}"

# Check for pattern extraction system
if [ -f "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" ]; then
    echo -e "${GREEN}   ✅ Pattern extraction system available${NC}"
else
    echo -e "${YELLOW}   ⚠️  Pattern extraction system not found - some features will be limited${NC}"
fi

command -v make >/dev/null 2>&1 || { 
    echo -e "${YELLOW}⚠️  Make not found - some commands will be unavailable${NC}"
}

# Step 2: Create .engineering directory and copy framework
echo -e "${BLUE}⚙️  Setting up local engineering framework...${NC}"
mkdir -p .engineering

# Copy global configurations
if [ -f "$ENGINEERING_GLOBAL/config.global.json" ]; then
    cp "$ENGINEERING_GLOBAL/config.global.json" .engineering/
    echo -e "${GREEN}   ✅ Global configuration deployed${NC}"
else
    echo -e "${RED}❌ Global configuration missing${NC}"
    exit 1
fi

# Create local configuration from template
if [ ! -f ".engineering/config.local.json" ]; then
    if [ -f "$ENGINEERING_GLOBAL/config.local.template.json" ]; then
        if command -v envsubst >/dev/null 2>&1; then
            envsubst < "$ENGINEERING_GLOBAL/config.local.template.json" > .engineering/config.local.json
            echo -e "${GREEN}   ✅ Local configuration created with environment substitution${NC}"
        else
            cp "$ENGINEERING_GLOBAL/config.local.template.json" .engineering/config.local.json
            echo -e "${YELLOW}   ⚠️  Local configuration created (envsubst not available for variable substitution)${NC}"
        fi
    else
        echo -e "${RED}❌ Local configuration template missing${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}   ✅ Local configuration already exists${NC}"
fi

# Copy enhanced pre-commit hook
if [ -f "$ENGINEERING_GLOBAL/pre-commit-hook.sh" ]; then
    cp "$ENGINEERING_GLOBAL/pre-commit-hook.sh" .engineering/
    echo -e "${GREEN}   ✅ Enhanced pre-commit hook copied${NC}"
fi

# Copy test harness
if [ -f "$ENGINEERING_GLOBAL/test-harness.sh" ]; then
    cp "$ENGINEERING_GLOBAL/test-harness.sh" .engineering/
    chmod +x .engineering/test-harness.sh
    echo -e "${GREEN}   ✅ Test harness deployed${NC}"
fi

# Step 3: Install git hooks for standards enforcement
echo -e "${BLUE}🪝 Installing git hooks with pattern integration...${NC}"
if [ -d ".git" ]; then
    if [ -f ".engineering/pre-commit-hook.sh" ]; then
        cp .engineering/pre-commit-hook.sh .git/hooks/pre-commit
        chmod +x .git/hooks/pre-commit
        echo -e "${GREEN}   ✅ Enhanced pre-commit hook installed${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Enhanced pre-commit hook not found, creating basic version${NC}"
        cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Basic standards enforcement hook with pattern integration
echo "🔍 Running enhanced pre-commit validation..."

# Check for LEARNINGS.md reference in commits involving code changes
if git diff --cached --name-only | grep -E "(src/|main\.js|index\.js)"; then
    if ! git diff --cached --name-only | grep -q "LEARNINGS.md"; then
        # Check if commit message mentions LEARNINGS patterns
        if [ -f ".git/COMMIT_EDITMSG" ] && grep -q "LEARNINGS\|patterns\|evidence" .git/COMMIT_EDITMSG; then
            echo "✅ LEARNINGS patterns referenced in commit"
        else
            echo "❌ COMMIT BLOCKED: Code changes require LEARNINGS.md consultation"
            echo "   Either update LEARNINGS.md or reference existing patterns in commit message"
            exit 1
        fi
    fi
fi

# Run smoke tests if available
if [ -f "package.json" ] && grep -q "test:smoke" package.json; then
    echo "🧪 Running smoke tests..."
    npm run test:smoke --silent || {
        echo "❌ COMMIT BLOCKED: Smoke tests failed"
        exit 1
    }
fi

# Run pattern extraction after successful commit
if [ -f "$HOME/.claude/scripts/extract-local-patterns.sh" ]; then
    echo "🎯 Extracting patterns post-commit..."
    ("$HOME/.claude/scripts/extract-local-patterns.sh" "$(pwd)" > /dev/null 2>&1) &
fi

echo "✅ Enhanced pre-commit validation passed"
EOF
        chmod +x .git/hooks/pre-commit
        echo -e "${GREEN}   ✅ Basic enhanced pre-commit hook created${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠️  Not a git repository - skipping git hooks${NC}"
fi

# Step 4: Set up test environment with pattern integration
echo -e "${BLUE}🧪 Configuring test environment with pattern support...${NC}"
if [ -f "package.json" ]; then
    if command -v npm >/dev/null 2>&1; then
        echo "   Installing dependencies..."
        npm install --silent || {
            echo -e "${YELLOW}   ⚠️  npm install failed - continuing anyway${NC}"
        }
        
        # Add pattern extraction to npm scripts if not present
        if ! grep -q "extract-patterns" package.json; then
            echo "   Adding pattern extraction script..."
            # Use jq if available for clean JSON modification
            if command -v jq >/dev/null 2>&1; then
                jq '.scripts["extract-patterns"] = "~/.claude/scripts/extract-local-patterns.sh $(pwd)"' package.json > package.json.tmp && mv package.json.tmp package.json
                jq '.scripts["claude-status"] = "~/.claude/scripts/evolution-report.sh dashboard"' package.json > package.json.tmp && mv package.json.tmp package.json
            else
                echo -e "${YELLOW}   ⚠️  jq not available - skipping automatic script addition${NC}"
            fi
        fi
        
        # Create test setup if it doesn't exist
        if grep -q "test:setup" package.json; then
            echo "   Running test setup..."
            npm run test:setup --silent || {
                echo -e "${YELLOW}   ⚠️  Test setup failed - continuing anyway${NC}"
            }
        fi
        
        echo -e "${GREEN}   ✅ Test environment configured with pattern support${NC}"
    else
        echo -e "${YELLOW}   ⚠️  npm not available - skipping dependency installation${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠️  No package.json found - creating basic one${NC}"
    cat > package.json << EOF
{
  "name": "$PROJECT_NAME",
  "version": "1.0.0",
  "scripts": {
    "extract-patterns": "~/.claude/scripts/extract-local-patterns.sh \$(pwd)",
    "claude-status": "~/.claude/scripts/evolution-report.sh dashboard",
    "test": "echo 'No tests specified'",
    "test:smoke": "echo 'No smoke tests configured'"
  }
}
EOF
    echo -e "${GREEN}   ✅ Basic package.json created with pattern integration${NC}"
fi

# Step 5: Create enhanced Makefile from global template
echo -e "${BLUE}📝 Setting up enhanced development commands...${NC}"
if [ ! -f "Makefile" ]; then
    if [ -f "$ENGINEERING_GLOBAL/Makefile.template" ]; then
        cp "$ENGINEERING_GLOBAL/Makefile.template" Makefile
        echo -e "${GREEN}   ✅ Enhanced Makefile deployed from template${NC}"
    else
        # Create enhanced Makefile with pattern integration
        cat > Makefile << 'EOF'
# Engineering Ethos Enhanced Makefile with Pattern Integration
# Deployed from ~/.claude/engineering framework

.PHONY: help setup investigate critical-bug test-critical validate-all patterns

help:
	@echo "Engineering Ethos Development Commands (Enhanced)"
	@echo ""
	@echo "Environment:"
	@echo "  setup              Initialize development environment"
	@echo "  validate-setup     Verify environment readiness"
	@echo ""
	@echo "Investigation:"
	@echo "  investigate        Standards-compliant investigation with pattern consultation"
	@echo "  critical-bug       Critical bug response protocol with pattern analysis"
	@echo ""
	@echo "Testing:"
	@echo "  test-critical      Run critical bug prevention tests"
	@echo "  test-smoke         Run basic functionality tests"
	@echo "  test-all           Complete test suite"
	@echo ""
	@echo "Pattern Management:"
	@echo "  extract-patterns   Extract patterns with evidence scoring"
	@echo "  claude-status      Show pattern evolution dashboard"
	@echo "  pattern-audit      Validate pattern usage in codebase"
	@echo ""
	@echo "Validation:"
	@echo "  validate-all       Complete standards compliance validation"
	@echo ""

setup:
	@bash ~/.claude/engineering/setup.sh $(shell pwd)

validate-setup:
	@echo "🔍 Validating enhanced environment setup..."
	@test -f .engineering/config.local.json || (echo "❌ Local config missing"; exit 1)
	@test -f .engineering/config.global.json || (echo "❌ Global config missing"; exit 1)
	@test -x .git/hooks/pre-commit || echo "⚠️  Git hooks not installed"
	@test -f ~/.claude/patterns/registry.json || echo "⚠️  Pattern registry not found"
	@echo "✅ Enhanced environment validation complete"

investigate:
	@echo "🔍 Starting enhanced investigation workflow..."
	@echo "📖 Step 1: LEARNINGS.md consultation (mandatory)"
	@test -f LEARNINGS.md && echo "   LEARNINGS.md found - review before proceeding" || echo "   ⚠️  LEARNINGS.md not found - consider creating one"
	@echo "📊 Step 2: Pattern registry consultation..."
	@test -f ~/.claude/patterns/registry.json && ~/.claude/scripts/evolution-report.sh dashboard | head -10 || echo "   Pattern registry not available"
	@echo "🧪 Step 3: Running diagnostic tests..."
	@if [ -f package.json ] && grep -q "test:smoke" package.json; then npm run test:smoke; fi
	@echo "📝 Step 4: Investigation environment ready with pattern context"

critical-bug:
	@echo "🚨 CRITICAL BUG RESPONSE PROTOCOL ACTIVATED - Enhanced Mode"
	@echo "📖 Emergency LEARNINGS.md and pattern registry review..."
	@test -f LEARNINGS.md && echo "   LEARNINGS.md available for emergency consultation" || echo "   ❌ LEARNINGS.md missing!"
	@test -f ~/.claude/patterns/registry.json && echo "   Pattern registry available for similar bug analysis" || echo "   ⚠️  Pattern registry not accessible"
	@echo "🧪 Running critical tests with pattern validation..."
	@if [ -f package.json ] && grep -q "test:critical" package.json; then npm run test:critical; fi
	@echo "🎯 Extracting patterns from current state..."
	@if [ -f ~/.claude/scripts/extract-local-patterns.sh ]; then ~/.claude/scripts/extract-local-patterns.sh $(shell pwd); fi
	@echo "🚨 Enhanced critical bug environment ready - HIGHEST STANDARD required"

extract-patterns:
	@echo "🎯 Extracting patterns with evidence scoring..."
	@if [ -f ~/.claude/scripts/extract-local-patterns.sh ]; then ~/.claude/scripts/extract-local-patterns.sh $(shell pwd); else echo "❌ Pattern extraction system not available"; fi

claude-status:
	@echo "📊 Pattern Evolution Dashboard:"
	@if [ -f ~/.claude/scripts/evolution-report.sh ]; then ~/.claude/scripts/evolution-report.sh dashboard; else echo "❌ Evolution reporting not available"; fi

pattern-audit:
	@echo "🔍 Auditing pattern usage in codebase..."
	@if [ -f LEARNINGS.md ]; then echo "✅ LEARNINGS.md found"; grep -c "Pattern\|✅\|❌" LEARNINGS.md | xargs -I {} echo "   {} patterns documented"; else echo "❌ No LEARNINGS.md found"; fi
	@if [ -f ~/.claude/patterns/registry.json ]; then echo "✅ Pattern registry accessible"; else echo "❌ Pattern registry not found"; fi

test-critical:
	@if [ -f .engineering/test-harness.sh ]; then ./.engineering/test-harness.sh critical; elif [ -f package.json ] && grep -q "test:critical" package.json; then npm run test:critical; else echo "⚠️  No critical tests defined"; fi

test-smoke:
	@if [ -f .engineering/test-harness.sh ]; then ./.engineering/test-harness.sh smoke; elif [ -f package.json ] && grep -q "test:smoke" package.json; then npm run test:smoke; else echo "⚠️  No smoke tests defined"; fi

test-all:
	@if [ -f .engineering/test-harness.sh ]; then ./.engineering/test-harness.sh all; elif [ -f package.json ]; then npm test; else echo "⚠️  No test command found"; fi

validate-all:
	@echo "🔍 Complete enhanced standards compliance validation..."
	@test -f LEARNINGS.md || (echo "❌ LEARNINGS.md missing"; exit 1)
	@test -f .engineering/config.global.json || (echo "❌ Global config missing"; exit 1)
	@test -f .engineering/config.local.json || (echo "❌ Local config missing"; exit 1)
	@if [ -f package.json ]; then node -c "require('./package.json')" || (echo "❌ package.json invalid"; exit 1); fi
	@if [ -f ~/.claude/patterns/registry.json ]; then echo "✅ Pattern registry accessible"; else echo "⚠️  Pattern registry not found"; fi
	@echo "✅ All enhanced validation passed"
EOF
        echo -e "${GREEN}   ✅ Enhanced Makefile created with pattern integration${NC}"
    fi
else
    echo -e "${GREEN}   ✅ Makefile already exists${NC}"
fi

# Step 6: Initialize pattern tracking for this project
echo -e "${BLUE}🎯 Initializing pattern tracking...${NC}"
if [ -f "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" ]; then
    echo "   Running initial pattern extraction..."
    "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" "$PROJECT_PATH" || {
        echo -e "${YELLOW}   ⚠️  Pattern extraction failed - continuing anyway${NC}"
    }
    echo -e "${GREEN}   ✅ Pattern tracking initialized${NC}"
else
    echo -e "${YELLOW}   ⚠️  Pattern extraction not available${NC}"
fi

# Step 7: Enhanced environment validation
echo -e "${BLUE}🔍 Validating enhanced environment...${NC}"

# Check for required documentation files
MISSING_DOCS=0
REQUIRED_DOCS=("LEARNINGS.md")
OPTIONAL_DOCS=("CLAUDE.md" "ENGINEERING_STANDARDS.md" "DEV_NARRATIVE.md" "ENGINEERING_ETHOS.md" "README.md")

for doc in "${REQUIRED_DOCS[@]}"; do
    if [ -f "$doc" ]; then
        echo -e "${GREEN}   ✅ $doc found${NC}"
    else
        echo -e "${YELLOW}   ⚠️  $doc missing (will be created)${NC}"
        MISSING_DOCS=1
    fi
done

for doc in "${OPTIONAL_DOCS[@]}"; do
    if [ -f "$doc" ]; then
        echo -e "${GREEN}   ✅ $doc found${NC}"
    else
        echo -e "${BLUE}   ℹ️  $doc optional${NC}"
    fi
done

# Check test configuration
if [ -f "package.json" ] && grep -q "test" package.json; then
    echo -e "${GREEN}   ✅ Test configuration found${NC}"
else
    echo -e "${YELLOW}   ⚠️  Test configuration incomplete${NC}"
fi

# Check pattern system integration
if [ -f "$CLAUDE_GLOBAL/patterns/registry.json" ]; then
    echo -e "${GREEN}   ✅ Pattern system integrated${NC}"
else
    echo -e "${YELLOW}   ⚠️  Pattern system not found${NC}"
fi

# Final status
echo ""
if [ $MISSING_DOCS -eq 0 ]; then
    echo -e "${GREEN}🎉 Enhanced Engineering Ethos environment deployed successfully!${NC}"
else
    echo -e "${YELLOW}🔧 Enhanced Engineering Ethos environment deployed with recommendations${NC}"
    echo -e "${YELLOW}   Consider creating LEARNINGS.md to enable full pattern tracking${NC}"
fi

echo ""
echo -e "${BLUE}Enhanced features available:${NC}"
echo -e "  ${GREEN}make extract-patterns${NC}           # Extract patterns with evidence scoring"
echo -e "  ${GREEN}make claude-status${NC}               # View pattern evolution dashboard"
echo -e "  ${GREEN}make investigate${NC}                 # Investigation with pattern consultation"
echo -e "  ${GREEN}make critical-bug${NC}                # Critical bug response with pattern analysis"
echo -e "  ${GREEN}make validate-all${NC}                # Complete enhanced validation"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Run ${GREEN}make validate-all${NC} to verify complete enhanced setup"
echo -e "  2. Use ${GREEN}make claude-status${NC} to see current pattern learning state"
echo -e "  3. Always start investigations with ${GREEN}make investigate${NC} for pattern-aware analysis"
echo -e "  4. Create/update ${GREEN}LEARNINGS.md${NC} to enable full pattern tracking benefits"
echo ""
echo -e "${GREEN}Engineering Ethos deployment complete with pattern integration! 🎯${NC}"