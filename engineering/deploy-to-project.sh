#!/bin/bash
# Engineering Ethos Universal Deployment Script
# Deploy enhanced Engineering Ethos to any project
# Version: 2.0 - Evidence-based with pattern integration

set -e

# Configuration
CLAUDE_GLOBAL="$HOME/.claude"
ENGINEERING_DIR="$CLAUDE_GLOBAL/engineering"
SCRIPT_NAME="$(basename "$0")"

# Color codes
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
log_header() { echo -e "${PURPLE}$1${NC}"; }

# Usage information
usage() {
    echo "Engineering Ethos Universal Deployment Script"
    echo ""
    echo "Usage: $SCRIPT_NAME [PROJECT_PATH] [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  PROJECT_PATH    Path to target project (default: current directory)"
    echo ""
    echo "Options:"
    echo "  --dry-run      Show what would be deployed without making changes"
    echo "  --force        Overwrite existing Engineering Ethos files"
    echo "  --minimal      Deploy minimal configuration only"
    echo "  --full         Deploy complete Engineering Ethos system (default)"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME                    # Deploy to current directory"
    echo "  $SCRIPT_NAME /path/to/project   # Deploy to specific project"
    echo "  $SCRIPT_NAME --dry-run          # Preview deployment"
    echo "  $SCRIPT_NAME --minimal          # Minimal deployment"
    echo ""
    exit 0
}

# Parse command line arguments
PROJECT_PATH="$(pwd)"
DRY_RUN=false
FORCE=false
MINIMAL=false
DEPLOYMENT_MODE="full"

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            usage
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --minimal)
            MINIMAL=true
            DEPLOYMENT_MODE="minimal"
            shift
            ;;
        --full)
            DEPLOYMENT_MODE="full"
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            PROJECT_PATH="$1"
            shift
            ;;
    esac
done

# Validation
if [ ! -d "$CLAUDE_GLOBAL" ]; then
    log_error "❌ Claude global directory not found: $CLAUDE_GLOBAL"
    log_error "   Initialize with: mkdir -p $CLAUDE_GLOBAL"
    exit 1
fi

if [ ! -d "$ENGINEERING_DIR" ]; then
    log_error "❌ Engineering Ethos not found: $ENGINEERING_DIR"
    log_error "   This script should be run from the Engineering Ethos installation"
    exit 1
fi

# Resolve and validate project path
PROJECT_PATH="$(realpath "$PROJECT_PATH" 2>/dev/null || echo "$PROJECT_PATH")"
if [ ! -d "$PROJECT_PATH" ]; then
    log_error "❌ Project directory not found: $PROJECT_PATH"
    exit 1
fi

PROJECT_NAME="$(basename "$PROJECT_PATH")"

# Header
log_header "🚀 Engineering Ethos Universal Deployment"
log_info "   Target Project: $PROJECT_NAME"
log_info "   Project Path: $PROJECT_PATH"
log_info "   Deployment Mode: $DEPLOYMENT_MODE"
log_info "   Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")"

# Deployment configuration
CORE_FILES="setup.sh pre-commit-hook.sh test-harness.sh config.global.json config.local.template.json Makefile.template"
OPTIONAL_FILES="deploy-to-project.sh"

# Detect project characteristics
detect_project_type() {
    log_info "🔍 Detecting project characteristics..."
    
    PROJECT_TYPE="unknown"
    HAS_PACKAGE_JSON=false
    HAS_GIT=false
    HAS_TESTS=false
    HAS_LEARNINGS=false
    
    if [ -f "$PROJECT_PATH/package.json" ]; then
        HAS_PACKAGE_JSON=true
        PROJECT_TYPE="node"
        log_success "   ✅ Node.js project detected"
    fi
    
    if [ -d "$PROJECT_PATH/.git" ]; then
        HAS_GIT=true
        log_success "   ✅ Git repository detected"
    else
        log_warning "   ⚠️ Not a git repository"
    fi
    
    if [ -d "$PROJECT_PATH/test" ] || [ -d "$PROJECT_PATH/tests" ] || [ -d "$PROJECT_PATH/__tests__" ]; then
        HAS_TESTS=true
        log_success "   ✅ Test directory detected"
    else
        log_warning "   ⚠️ No test directory found"
    fi
    
    if [ -f "$PROJECT_PATH/LEARNINGS.md" ]; then
        HAS_LEARNINGS=true
        LEARNINGS_LINES=$(wc -l < "$PROJECT_PATH/LEARNINGS.md" 2>/dev/null || echo "0")
        log_success "   ✅ LEARNINGS.md found ($LEARNINGS_LINES lines)"
    else
        log_warning "   ⚠️ No LEARNINGS.md found"
    fi
}

# Check for existing Engineering Ethos installation
check_existing_installation() {
    log_info "🔍 Checking existing Engineering Ethos installation..."
    
    ENGINEERING_LOCAL="$PROJECT_PATH/.engineering"
    HAS_ENGINEERING=false
    
    if [ -d "$ENGINEERING_LOCAL" ]; then
        HAS_ENGINEERING=true
        FILE_COUNT=$(find "$ENGINEERING_LOCAL" -type f | wc -l)
        log_warning "   ⚠️ Existing .engineering directory found ($FILE_COUNT files)"
        
        if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
            log_error "   ❌ Use --force to overwrite existing installation"
            exit 1
        fi
    else
        log_success "   ✅ No existing installation found"
    fi
}

# Create deployment manifest
create_deployment_manifest() {
    log_info "📋 Creating deployment manifest..."
    
    MANIFEST_FILE="$PROJECT_PATH/.engineering/deployment-manifest.json"
    
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$(dirname "$MANIFEST_FILE")"
        
        cat > "$MANIFEST_FILE" << EOF
{
  "engineering_ethos": {
    "version": "2.0",
    "deployment_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "deployment_mode": "$DEPLOYMENT_MODE",
    "project_characteristics": {
      "name": "$PROJECT_NAME",
      "type": "$PROJECT_TYPE",
      "has_package_json": $HAS_PACKAGE_JSON,
      "has_git": $HAS_GIT,
      "has_tests": $HAS_TESTS,
      "has_learnings": $HAS_LEARNINGS
    },
    "deployed_files": []
  }
}
EOF
        log_success "   ✅ Deployment manifest created"
    else
        log_info "   📋 Would create: $MANIFEST_FILE"
    fi
}

# Deploy files
deploy_files() {
    log_info "📂 Deploying Engineering Ethos files..."
    
    ENGINEERING_LOCAL="$PROJECT_PATH/.engineering"
    DEPLOYED_COUNT=0
    
    # Create engineering directory
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$ENGINEERING_LOCAL"
    else
        log_info "   📁 Would create: $ENGINEERING_LOCAL"
    fi
    
    # Deploy core files
    for file in $CORE_FILES; do
        SOURCE="$ENGINEERING_DIR/$file"
        TARGET="$ENGINEERING_LOCAL/$file"
        
        # Set description based on file
        case "$file" in
            "setup.sh") DESCRIPTION="Enhanced setup script with pattern integration" ;;
            "pre-commit-hook.sh") DESCRIPTION="Real enforcement pre-commit hook" ;;
            "test-harness.sh") DESCRIPTION="Pattern-integrated test orchestration" ;;
            "config.global.json") DESCRIPTION="Engineering standards configuration" ;;
            "config.local.template.json") DESCRIPTION="Project-specific configuration template" ;;
            "Makefile.template") DESCRIPTION="Engineering automation makefile" ;;
            *) DESCRIPTION="Engineering Ethos file" ;;
        esac
        
        if [ -f "$SOURCE" ]; then
            if [ "$DRY_RUN" = false ]; then
                cp "$SOURCE" "$TARGET"
                chmod +x "$TARGET" 2>/dev/null || true
                
                # Update deployment manifest
                if [ -f "$MANIFEST_FILE" ]; then
                    jq ".engineering_ethos.deployed_files += [\"$file\"]" "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
                fi
                
                log_success "   ✅ Deployed: $file - $DESCRIPTION"
            else
                log_info "   📄 Would deploy: $file - $DESCRIPTION"
            fi
            DEPLOYED_COUNT=$((DEPLOYED_COUNT + 1))
        else
            log_error "   ❌ Source file not found: $SOURCE"
        fi
    done
    
    # Deploy optional files if full mode
    if [ "$DEPLOYMENT_MODE" = "full" ]; then
        for file in $OPTIONAL_FILES; do
            SOURCE="$ENGINEERING_DIR/$file"
            TARGET="$ENGINEERING_LOCAL/$file"
            
            # Set description based on file
            case "$file" in
                "deploy-to-project.sh") DESCRIPTION="Universal deployment script" ;;
                *) DESCRIPTION="Optional Engineering Ethos file" ;;
            esac
            
            if [ -f "$SOURCE" ]; then
                if [ "$DRY_RUN" = false ]; then
                    cp "$SOURCE" "$TARGET"
                    chmod +x "$TARGET" 2>/dev/null || true
                    
                    if [ -f "$MANIFEST_FILE" ]; then
                        jq ".engineering_ethos.deployed_files += [\"$file\"]" "$MANIFEST_FILE" > "${MANIFEST_FILE}.tmp" && mv "${MANIFEST_FILE}.tmp" "$MANIFEST_FILE"
                    fi
                    
                    log_success "   ✅ Deployed: $file - $DESCRIPTION"
                else
                    log_info "   📄 Would deploy: $file - $DESCRIPTION"
                fi
                DEPLOYED_COUNT=$((DEPLOYED_COUNT + 1))
            fi
        done
    fi
    
    log_info "   📊 Total files: $DEPLOYED_COUNT"
}

# Create project-specific configuration
create_project_config() {
    log_info "⚙️ Creating project-specific configuration..."
    
    CONFIG_FILE="$PROJECT_PATH/.engineering/config.local.json"
    
    if [ "$DRY_RUN" = false ]; then
        # Copy template and customize
        cp "$PROJECT_PATH/.engineering/config.local.template.json" "$CONFIG_FILE"
        
        # Update project-specific fields using jq if available
        if command -v jq >/dev/null 2>&1; then
            # Update main files based on project structure
            if [ -f "$PROJECT_PATH/src/main.js" ]; then
                jq '.project_specifics.main_files = ["src/main.js"]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            elif [ -f "$PROJECT_PATH/main.js" ]; then
                jq '.project_specifics.main_files = ["main.js"]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi
            
            # Update test directories
            if [ -d "$PROJECT_PATH/test" ]; then
                jq '.project_specifics.test_directories = ["test/"]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            elif [ -d "$PROJECT_PATH/tests" ]; then
                jq '.project_specifics.test_directories = ["tests/"]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            fi
        fi
        
        log_success "   ✅ Project configuration created: config.local.json"
    else
        log_info "   ⚙️ Would create: config.local.json"
    fi
}

# Install git hooks
install_git_hooks() {
    if [ "$HAS_GIT" = true ]; then
        log_info "🪝 Installing git hooks..."
        
        HOOKS_DIR="$PROJECT_PATH/.git/hooks"
        PRE_COMMIT_HOOK="$HOOKS_DIR/pre-commit"
        
        if [ "$DRY_RUN" = false ]; then
            cp "$PROJECT_PATH/.engineering/pre-commit-hook.sh" "$PRE_COMMIT_HOOK"
            chmod +x "$PRE_COMMIT_HOOK"
            log_success "   ✅ Pre-commit hook installed"
        else
            log_info "   🪝 Would install: pre-commit hook"
        fi
    else
        log_warning "   ⚠️ Skipping git hooks (not a git repository)"
    fi
}

# Create Makefile
create_makefile() {
    log_info "🔧 Setting up project Makefile..."
    
    MAKEFILE_PATH="$PROJECT_PATH/Makefile"
    
    if [ -f "$MAKEFILE_PATH" ] && [ "$FORCE" = false ]; then
        log_warning "   ⚠️ Makefile exists - creating Makefile.engineering instead"
        MAKEFILE_PATH="$PROJECT_PATH/Makefile.engineering"
    fi
    
    if [ "$DRY_RUN" = false ]; then
        cp "$PROJECT_PATH/.engineering/Makefile.template" "$MAKEFILE_PATH"
        log_success "   ✅ Makefile created: $(basename "$MAKEFILE_PATH")"
    else
        log_info "   🔧 Would create: $(basename "$MAKEFILE_PATH")"
    fi
}

# Initialize LEARNINGS.md if needed
initialize_learnings() {
    if [ "$HAS_LEARNINGS" = false ]; then
        log_info "📖 Initializing LEARNINGS.md..."
        
        LEARNINGS_PATH="$PROJECT_PATH/LEARNINGS.md"
        
        if [ "$DRY_RUN" = false ]; then
            cat > "$LEARNINGS_PATH" << EOF
# LEARNINGS.md - Engineering Knowledge Base

## Engineering Ethos Deployment

### Pattern 1.0 - Initial Engineering Ethos Setup
- **Date**: $(date +"%Y-%m-%d")
- **Context**: Deployed Engineering Ethos v2.0 to $PROJECT_NAME
- **Pattern**: Universal deployment with pattern integration
- **Evidence**: ✅ Deployment completed successfully
- **Lesson**: Engineering Ethos provides systematic approach to quality

## Project Patterns

*Document patterns, bugs, and lessons learned here*

### Pattern Template
- **Date**: YYYY-MM-DD
- **Context**: Brief description of situation
- **Pattern**: What pattern was applied or discovered
- **Evidence**: ✅/❌ Observable outcome
- **Lesson**: Key insight for future reference

## JDEP Applications

*Document Jeff Dean Engineering Protocol applications*

### JDEP Template
1. **Investigation**: Root cause analysis
2. **Design**: Solution architecture
3. **Evidence**: Supporting data
4. **Prevention**: Mechanisms to prevent recurrence

---

*This file is the institutional memory of the project. Keep it updated with every significant change.*
EOF
            log_success "   ✅ LEARNINGS.md initialized with template"
        else
            log_info "   📖 Would create: LEARNINGS.md"
        fi
    else
        log_success "   ✅ LEARNINGS.md already exists"
    fi
}

# Integration with pattern extraction system
integrate_patterns() {
    log_info "🎯 Integrating with pattern extraction system..."
    
    PATTERN_REGISTRY="$CLAUDE_GLOBAL/patterns/registry.json"
    
    if [ -f "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" ]; then
        if [ "$DRY_RUN" = false ]; then
            log_info "   Running initial pattern extraction..."
            "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" "$PROJECT_PATH" || log_warning "   ⚠️ Pattern extraction completed with warnings"
            log_success "   ✅ Pattern extraction integration complete"
        else
            log_info "   🎯 Would run: pattern extraction"
        fi
    else
        log_warning "   ⚠️ Pattern extraction script not found"
    fi
}

# Generate deployment report
generate_report() {
    log_header "📊 Engineering Ethos Deployment Report"
    echo ""
    log_info "Project: $PROJECT_NAME"
    log_info "Path: $PROJECT_PATH"
    log_info "Mode: $DEPLOYMENT_MODE"
    log_info "Type: $PROJECT_TYPE"
    echo ""
    
    log_success "✅ Deployment Summary:"
    echo "   - Engineering Ethos v2.0 $([ "$DRY_RUN" = true ] && echo "(dry-run)" || echo "deployed")"
    echo "   - Enhanced enforcement mechanisms $([ "$DRY_RUN" = true ] && echo "planned" || echo "active")"
    echo "   - Pattern integration $([ "$DRY_RUN" = true ] && echo "planned" || echo "configured")"
    echo "   - Git hooks $([ "$HAS_GIT" = true ] && echo "$([ "$DRY_RUN" = true ] && echo "planned" || echo "installed")" || echo "skipped (no git)")"
    echo "   - LEARNINGS.md $([ "$HAS_LEARNINGS" = true ] && echo "exists" || echo "$([ "$DRY_RUN" = true ] && echo "planned" || echo "created")")"
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        log_success "🚀 Next Steps:"
        echo "   1. Review configuration: .engineering/config.local.json"
        echo "   2. Run validation: make validate"
        echo "   3. Start development: make dev-setup"
        echo "   4. View status: make status"
        echo ""
        echo "   For help: make help"
    else
        log_info "🚀 To proceed with deployment:"
        echo "   Run: $SCRIPT_NAME \"$PROJECT_PATH\""
    fi
}

# Main deployment process
main() {
    detect_project_type
    check_existing_installation
    
    if [ "$DRY_RUN" = false ]; then
        create_deployment_manifest
    fi
    
    deploy_files
    
    if [ "$DRY_RUN" = false ]; then
        create_project_config
        install_git_hooks
        create_makefile
        initialize_learnings
        integrate_patterns
    fi
    
    generate_report
}

# Execute main function
main

log_success "$([ "$DRY_RUN" = true ] && echo "🔍 Dry-run complete" || echo "✅ Engineering Ethos deployment complete")"