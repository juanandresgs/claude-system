# RULES.md - SuperClaude Framework Actionable Rules

Simple actionable rules for Claude Code SuperClaude framework operation.

## Core Operational Rules

### Task Management Rules
- TodoRead() → TodoWrite(3+ tasks) → Execute → Track progress
- Use batch tool calls when possible, sequential only when dependencies exist
- Always validate before execution, verify after completion
- Run lint/typecheck before marking tasks complete
- Use /spawn and /task for complex multi-session workflows
- Maintain ≥90% context retention across operations

### File Operation Security
- Always use Read tool before Write or Edit operations
- Use absolute paths only, prevent path traversal attacks
- Prefer batch operations and transaction-like behavior
- Never commit automatically unless explicitly requested

### Framework Compliance
- Check package.json/pyproject.toml before using libraries
- Follow existing project patterns and conventions
- Use project's existing import styles and organization
- Respect framework lifecycles and best practices

### Systematic Codebase Changes
- **MANDATORY**: Complete project-wide discovery before any changes
- Search ALL file types for ALL variations of target terms
- Document all references with context and impact assessment
- Plan update sequence based on dependencies and relationships
- Execute changes in coordinated manner following plan
- Verify completion with comprehensive post-change search
- Validate related functionality remains working
- Use Task tool for comprehensive searches when scope uncertain

### Knowledge Base Precedence Rules (CRITICAL - Prevents Regression)
- **BEFORE ANY API CHANGE**: Search LEARNINGS.md for existing patterns
- **EXISTING PATTERNS WITH ✅**: Use them EXACTLY as documented
- **EXISTING PATTERNS WITH ❌**: NEVER use them, they are proven failures
- **BEFORE CHANGING WORKING CODE**: Verify why current code works first
- **REGRESSION CHECK**: Search git history for "already fixed this" patterns
- **EXTERNAL API VALIDATION**: Test against real APIs, not just mocks
- **DOCUMENTATION PRECEDENCE**: Existing knowledge beats innovation assumptions
- **INSTITUTIONAL MEMORY**: The most dangerous bugs are ones we already fixed but forgot

## Quick Reference

### Do
✅ Read before Write/Edit/Update
✅ Use absolute paths
✅ Batch tool calls
✅ Validate before execution
✅ Check framework compatibility
✅ Auto-activate personas
✅ Preserve context across operations
✅ Use quality gates (see ORCHESTRATOR.md)
✅ Complete discovery before codebase changes
✅ Verify completion with evidence
✅ Search LEARNINGS.md before changing ANY API
✅ Follow existing ✅ patterns exactly
✅ Avoid existing ❌ patterns completely

### Don't
❌ Skip Read operations
❌ Use relative paths
❌ Auto-commit without permission
❌ Ignore framework patterns
❌ Skip validation steps
❌ Mix user-facing content in config
❌ Override safety protocols
❌ Make reactive codebase changes
❌ Mark complete without verification
❌ Change working APIs without knowledge base check
❌ Trust test mocks over real API behavior
❌ Ignore existing ✅ patterns for "innovation"

### Auto-Triggers
- Wave mode: complexity ≥0.7 + multiple domains
- Personas: domain keywords + complexity assessment  
- MCP servers: task type + performance requirements
- Quality gates: all operations apply 8-step validation