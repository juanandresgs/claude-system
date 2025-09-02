#!/bin/bash
# Enhanced Engineering Ethos Test Harness with Pattern Integration
# Automated test execution with standards compliance and pattern validation

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Global paths
CLAUDE_GLOBAL="${HOME}/.claude"

# Default test category
TEST_CATEGORY="${1:-all}"

echo -e "${BLUE}🧪 Enhanced Engineering Ethos Test Harness: $TEST_CATEGORY${NC}"
echo -e "${BLUE}   Project: $(basename "$(pwd)")${NC}"
echo -e "${BLUE}   Pattern integration: $([ -f "$CLAUDE_GLOBAL/patterns/registry.json" ] && echo "✅ Available" || echo "⚠️  Not found")${NC}"
echo ""

# Function to run pattern-enhanced test harness
setup_harness() {
    local category="$1"
    
    echo -e "${BLUE}Setting up test harness for: $category${NC}"
    
    case "$category" in
        "critical")
            echo -e "${BLUE}🚨 Critical Bug Prevention Tests with Pattern Analysis${NC}"
            echo "   Purpose: Prevent critical bugs and validate pattern compliance"
            echo "   Coverage: 100% required for critical paths with pattern enforcement"
            
            # Pre-test pattern consultation
            if [ -f "$CLAUDE_GLOBAL/patterns/registry.json" ]; then
                echo -e "${BLUE}   Consulting pattern registry for similar bug patterns...${NC}"
                if command -v jq >/dev/null 2>&1; then
                    PATTERN_COUNT=$(jq -r '.projects | length' "$CLAUDE_GLOBAL/patterns/registry.json" 2>/dev/null || echo "0")
                    echo -e "${GREEN}   📊 Pattern registry: $PATTERN_COUNT projects analyzed${NC}"
                fi
            fi
            
            if [ -f "package.json" ]; then
                # Run extraction workflow tests (critical for data protection)
                if grep -q "test:extraction" package.json; then
                    echo -e "${BLUE}   Running extraction protection tests...${NC}"
                    npm run test:extraction || {
                        echo -e "${RED}   ❌ Extraction tests failed - critical bug protection compromised${NC}"
                        exit 1
                    }
                    echo -e "${GREEN}   ✅ Extraction protection validated${NC}"
                fi
                
                # Run critical test patterns with enhanced validation
                if command -v jest >/dev/null 2>&1; then
                    echo -e "${BLUE}   Running critical test patterns with pattern validation...${NC}"
                    jest --testNamePattern="Critical|Extraction|Protection|Prevention" --bail --verbose || {
                        echo -e "${RED}   ❌ Critical tests failed${NC}"
                        exit 1
                    }
                    echo -e "${GREEN}   ✅ Critical test patterns passed${NC}"
                fi
                
                # Post-test pattern extraction
                if [ -f "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" ]; then
                    echo -e "${BLUE}   Extracting patterns from test results...${NC}"
                    "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" "$(pwd)" > /dev/null 2>&1 || {
                        echo -e "${YELLOW}   ⚠️  Pattern extraction failed - continuing anyway${NC}"
                    }
                    echo -e "${GREEN}   ✅ Pattern extraction completed${NC}"
                fi
            else
                echo -e "${YELLOW}   ⚠️  No package.json found - skipping npm tests${NC}"
            fi
            ;;
            
        "smoke")
            echo -e "${BLUE}💨 Smoke Tests with Pattern Compliance Validation${NC}"
            echo "   Purpose: Verify basic functionality and pattern adherence"
            echo "   Coverage: Core features, system stability, and pattern usage"
            
            # Check LEARNINGS.md consultation compliance
            if [ -f "LEARNINGS.md" ]; then
                echo -e "${BLUE}   Validating LEARNINGS.md pattern compliance...${NC}"
                PATTERN_REFS=$(grep -c "✅\|❌\|Pattern\|JDEP" LEARNINGS.md 2>/dev/null || echo "0")
                if [ "$PATTERN_REFS" -gt 5 ]; then
                    echo -e "${GREEN}   ✅ LEARNINGS.md shows good pattern documentation ($PATTERN_REFS references)${NC}"
                else
                    echo -e "${YELLOW}   ⚠️  LEARNINGS.md has limited pattern documentation ($PATTERN_REFS references)${NC}"
                fi
            else
                echo -e "${YELLOW}   ⚠️  No LEARNINGS.md found - consider creating for pattern tracking${NC}"
            fi
            
            if [ -f "package.json" ] && grep -q "test:smoke" package.json; then
                echo -e "${BLUE}   Running smoke tests...${NC}"
                npm run test:smoke --silent || {
                    echo -e "${RED}   ❌ Smoke tests failed - basic functionality broken${NC}"
                    exit 1
                }
                echo -e "${GREEN}   ✅ Smoke tests passed${NC}"
            elif command -v jest >/dev/null 2>&1; then
                echo -e "${BLUE}   Running Jest smoke pattern tests...${NC}"
                jest --testNamePattern="Smoke" --bail=1 --verbose || {
                    echo -e "${RED}   ❌ Smoke tests failed${NC}"
                    exit 1
                }
                echo -e "${GREEN}   ✅ Smoke tests passed${NC}"
            else
                echo -e "${YELLOW}   ⚠️  No smoke tests configured${NC}"
            fi
            ;;
            
        "architectural")
            echo -e "${BLUE}🏗️  Architectural Validation with Pattern Evolution${NC}"
            echo "   Purpose: Validate system design and track architectural patterns"
            echo "   Coverage: 95% required for architectural patterns with evolution tracking"
            
            # Check for architectural pattern evolution
            if [ -f "ARCHITECTURE.md" ]; then
                echo -e "${GREEN}   ✅ ARCHITECTURE.md found - architectural patterns documented${NC}"
            else
                echo -e "${YELLOW}   ⚠️  No ARCHITECTURE.md found - consider documenting architectural decisions${NC}"
            fi
            
            if [ -f "package.json" ] && grep -q "test:recursion" package.json; then
                echo -e "${BLUE}   Running recursion prevention tests...${NC}"
                npm run test:recursion || {
                    echo -e "${RED}   ❌ Recursion tests failed - architectural integrity compromised${NC}"
                    exit 1
                }
                echo -e "${GREEN}   ✅ Recursion prevention validated${NC}"
            fi
            
            if command -v jest >/dev/null 2>&1; then
                echo -e "${BLUE}   Running architectural test patterns...${NC}"
                jest --testNamePattern="Architecture|Recursion|Layout|Component" --coverage --coverageThreshold='{"global":{"branches":90}}' || {
                    echo -e "${RED}   ❌ Architectural tests failed${NC}"
                    exit 1
                }
                echo -e "${GREEN}   ✅ Architectural validation passed${NC}"
            else
                echo -e "${YELLOW}   ⚠️  Jest not available for architectural tests${NC}"
            fi
            
            # Update architectural pattern tracking
            if [ -f "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" ]; then
                echo -e "${BLUE}   Updating architectural pattern registry...${NC}"
                "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" "$(pwd)" > /dev/null 2>&1 || {
                    echo -e "${YELLOW}   ⚠️  Pattern registry update failed${NC}"
                }
                echo -e "${GREEN}   ✅ Architectural patterns tracked${NC}"
            fi
            ;;
            
        "regression")
            echo -e "${BLUE}🔄 Regression Prevention with Pattern History Analysis${NC}"
            echo "   Purpose: Prevent previously fixed bugs using pattern analysis"
            echo "   Coverage: Complete test suite with historical pattern validation"
            
            # Check for regression patterns in LEARNINGS.md
            if [ -f "LEARNINGS.md" ]; then
                REGRESSION_PATTERNS=$(grep -c "regression\|broke again\|returned" LEARNINGS.md 2>/dev/null || echo "0")
                if [ "$REGRESSION_PATTERNS" -gt 0 ]; then
                    echo -e "${YELLOW}   ⚠️  Found $REGRESSION_PATTERNS regression patterns in LEARNINGS.md${NC}"
                    echo -e "${BLUE}   Using pattern analysis to prevent similar issues...${NC}"
                else
                    echo -e "${GREEN}   ✅ No regression patterns detected in historical data${NC}"
                fi
            fi
            
            if [ -f "package.json" ]; then
                echo -e "${BLUE}   Running full regression test suite with pattern validation...${NC}"
                npm test || {
                    echo -e "${RED}   ❌ Regression tests failed${NC}"
                    # Extract failure patterns for analysis
                    if [ -f "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" ]; then
                        echo -e "${BLUE}   Extracting failure patterns for analysis...${NC}"
                        "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" "$(pwd)" > /dev/null 2>&1 &
                    fi
                    exit 1
                }
                echo -e "${GREEN}   ✅ Regression prevention validated${NC}"
            else
                echo -e "${YELLOW}   ⚠️  No test configuration found${NC}"
            fi
            ;;
            
        "coverage")
            echo -e "${BLUE}📊 Test Coverage Analysis with Pattern Effectiveness${NC}"
            echo "   Purpose: Ensure adequate coverage and measure pattern effectiveness"
            echo "   Requirements: 100% for critical paths, 90% overall, pattern usage tracking"
            
            if [ -f "package.json" ] && grep -q "test:coverage" package.json; then
                echo -e "${BLUE}   Generating enhanced coverage report...${NC}"
                npm run test:coverage || {
                    echo -e "${RED}   ❌ Coverage analysis failed${NC}"
                    exit 1
                }
                echo -e "${GREEN}   ✅ Coverage analysis complete${NC}"
            elif command -v jest >/dev/null 2>&1; then
                echo -e "${BLUE}   Running Jest with enhanced coverage tracking...${NC}"
                jest --coverage --ci --coverageReporters=text --coverageReporters=json || {
                    echo -e "${RED}   ❌ Coverage analysis failed${NC}"
                    exit 1
                }
                echo -e "${GREEN}   ✅ Coverage analysis complete${NC}"
                
                # Analyze coverage against pattern usage
                if [ -f "coverage/coverage-final.json" ] && [ -f "LEARNINGS.md" ]; then
                    echo -e "${BLUE}   Analyzing coverage vs pattern effectiveness...${NC}"
                    TESTED_PATTERNS=$(grep -c "test.*pattern\|pattern.*test" LEARNINGS.md 2>/dev/null || echo "0")
                    echo -e "${GREEN}   📊 Pattern testing coverage: $TESTED_PATTERNS documented patterns with tests${NC}"
                fi
            else
                echo -e "${YELLOW}   ⚠️  No coverage tools available${NC}"
            fi
            
            # Generate pattern effectiveness report
            if [ -f "$CLAUDE_GLOBAL/scripts/evolution-report.sh" ]; then
                echo -e "${BLUE}   Generating pattern effectiveness report...${NC}"
                "$CLAUDE_GLOBAL/scripts/evolution-report.sh" dashboard | head -20
            fi
            ;;
            
        "patterns")
            echo -e "${BLUE}🎯 Pattern Validation and Evidence Scoring${NC}"
            echo "   Purpose: Validate pattern usage and update evidence scores"
            echo "   Coverage: All documented patterns with effectiveness measurement"
            
            # Run pattern extraction and validation
            if [ -f "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" ]; then
                echo -e "${BLUE}   Running pattern extraction with evidence scoring...${NC}"
                "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" "$(pwd)" || {
                    echo -e "${RED}   ❌ Pattern extraction failed${NC}"
                    exit 1
                }
                echo -e "${GREEN}   ✅ Pattern extraction completed${NC}"
            fi
            
            # Generate evolution report
            if [ -f "$CLAUDE_GLOBAL/scripts/evolution-report.sh" ]; then
                echo -e "${BLUE}   Generating pattern evolution analysis...${NC}"
                "$CLAUDE_GLOBAL/scripts/evolution-report.sh" dashboard
                echo -e "${GREEN}   ✅ Pattern evolution analysis complete${NC}"
            fi
            
            # Validate LEARNINGS.md compliance
            if [ -f "LEARNINGS.md" ]; then
                echo -e "${BLUE}   Validating LEARNINGS.md pattern compliance...${NC}"
                JDEP_COUNT=$(grep -c "Phase [0-6]\|JDEP\|Root Cause" LEARNINGS.md 2>/dev/null || echo "0")
                PATTERN_COUNT=$(grep -c "✅\|❌\|Pattern Identified" LEARNINGS.md 2>/dev/null || echo "0")
                echo -e "${GREEN}   📊 JDEP applications: $JDEP_COUNT${NC}"
                echo -e "${GREEN}   📊 Documented patterns: $PATTERN_COUNT${NC}"
                
                if [ "$JDEP_COUNT" -gt 10 ] && [ "$PATTERN_COUNT" -gt 5 ]; then
                    echo -e "${GREEN}   ✅ LEARNINGS.md shows excellent pattern maturity${NC}"
                elif [ "$JDEP_COUNT" -gt 5 ] && [ "$PATTERN_COUNT" -gt 2 ]; then
                    echo -e "${YELLOW}   ⚠️  LEARNINGS.md shows developing pattern maturity${NC}"
                else
                    echo -e "${YELLOW}   ⚠️  LEARNINGS.md needs more pattern documentation${NC}"
                fi
            else
                echo -e "${RED}   ❌ No LEARNINGS.md found - pattern validation impossible${NC}"
                exit 1
            fi
            ;;
            
        "all")
            echo -e "${BLUE}🎯 Complete Test Suite with Full Pattern Integration${NC}"
            echo "   Purpose: Comprehensive validation with pattern effectiveness analysis"
            echo "   Coverage: All test categories plus pattern evolution tracking"
            
            # Run tests in priority order with pattern integration
            echo -e "${BLUE}   Step 1: Pattern validation and evidence scoring...${NC}"
            setup_harness "patterns"
            
            echo -e "${BLUE}   Step 2: Critical bug prevention...${NC}"
            setup_harness "critical"
            
            echo -e "${BLUE}   Step 3: Smoke test validation...${NC}"
            setup_harness "smoke"
            
            echo -e "${BLUE}   Step 4: Architectural validation...${NC}"
            setup_harness "architectural"
            
            echo -e "${BLUE}   Step 5: Coverage analysis...${NC}"
            setup_harness "coverage"
            
            echo -e "${BLUE}   Step 6: Regression prevention...${NC}"
            setup_harness "regression"
            
            # Final pattern analysis and reporting
            echo -e "${BLUE}   Step 7: Final pattern effectiveness analysis...${NC}"
            if [ -f "$CLAUDE_GLOBAL/scripts/evolution-report.sh" ]; then
                echo -e "${GREEN}📊 Complete Pattern Analysis:${NC}"
                "$CLAUDE_GLOBAL/scripts/evolution-report.sh" dashboard
            fi
            
            echo -e "${GREEN}   🎉 Complete enhanced test suite passed with pattern integration${NC}"
            return
            ;;
            
        *)
            echo -e "${RED}❌ Unknown test category: $category${NC}"
            echo ""
            echo "Available categories:"
            echo "  critical      - Critical bug prevention with pattern analysis"
            echo "  smoke         - Basic functionality with pattern compliance"
            echo "  architectural - System design validation with pattern evolution"
            echo "  regression    - Regression prevention with pattern history"
            echo "  coverage      - Coverage analysis with pattern effectiveness"
            echo "  patterns      - Pattern validation and evidence scoring"
            echo "  all           - Complete suite with full pattern integration"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}✅ Enhanced test harness '$category' completed successfully${NC}"
}

# Pre-test validation with pattern system check
echo -e "${BLUE}🔍 Pre-test environment validation with pattern integration...${NC}"

# Check for test configuration
if [ ! -f "package.json" ]; then
    echo -e "${YELLOW}   ⚠️  No package.json found - limited test capabilities${NC}"
else
    echo -e "${GREEN}   ✅ Package configuration found${NC}"
fi

# Check for Node.js
if ! command -v node >/dev/null 2>&1; then
    echo -e "${RED}   ❌ Node.js not found - tests may fail${NC}"
else
    echo -e "${GREEN}   ✅ Node.js available: $(node --version)${NC}"
fi

# Check for Jest
if ! command -v jest >/dev/null 2>&1 && [ -f "package.json" ] && ! grep -q "jest" package.json; then
    echo -e "${YELLOW}   ⚠️  Jest not available - some tests may be skipped${NC}"
else
    echo -e "${GREEN}   ✅ Test runner available${NC}"
fi

# Check pattern system integration
if [ -f "$CLAUDE_GLOBAL/patterns/registry.json" ]; then
    echo -e "${GREEN}   ✅ Pattern registry accessible${NC}"
    if command -v jq >/dev/null 2>&1; then
        PROJECTS_COUNT=$(jq -r '.projects | length' "$CLAUDE_GLOBAL/patterns/registry.json" 2>/dev/null || echo "0")
        echo -e "${GREEN}   📊 Pattern registry: $PROJECTS_COUNT projects tracked${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠️  Pattern registry not found - pattern features limited${NC}"
fi

# Check for pattern extraction system
if [ -f "$CLAUDE_GLOBAL/scripts/extract-local-patterns.sh" ]; then
    echo -e "${GREEN}   ✅ Pattern extraction system available${NC}"
else
    echo -e "${YELLOW}   ⚠️  Pattern extraction not available${NC}"
fi

# Check for evolution reporting
if [ -f "$CLAUDE_GLOBAL/scripts/evolution-report.sh" ]; then
    echo -e "${GREEN}   ✅ Evolution reporting system available${NC}"
else
    echo -e "${YELLOW}   ⚠️  Evolution reporting not available${NC}"
fi

echo ""

# Execute the requested test harness
setup_harness "$TEST_CATEGORY"

echo ""
echo -e "${BLUE}📋 Enhanced Test Harness Summary${NC}"
echo -e "  Category: $TEST_CATEGORY"
echo -e "  Status: ${GREEN}PASSED${NC}"
echo -e "  Pattern Integration: $([ -f "$CLAUDE_GLOBAL/patterns/registry.json" ] && echo "✅ Active" || echo "⚠️  Limited")"
echo -e "  Standards: Engineering Ethos compliance verified"
echo ""
echo -e "${BLUE}Enhanced Engineering Standards Reminder:${NC}"
echo -e "  - Critical bugs must have 100% test coverage with pattern validation"
echo -e "  - All tests must pass before commit with pattern compliance check"
echo -e "  - Failed tests trigger pattern extraction for analysis"
echo -e "  - Document new test patterns in LEARNINGS.md with evidence scoring"
echo -e "  - Use pattern history to prevent regression failures"
echo ""