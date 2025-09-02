# Developer Guide - Claude System

**Comprehensive Developer Reference for Claude Code SuperClaude Framework**  
**Target Audience**: Developers, contributors, higher reasoning models

---

## 🚀 Quick Start for Developers

### System Overview
The Claude System is a production-ready AI command framework that enhances Claude Code with intelligent automation while maintaining user control and system simplicity.

```bash
# Clone and explore (private repository)
git clone https://github.com/juanandresgs/claude-system.git ~/.claude
cd ~/.claude

# Check system health
ls *.md | wc -l          # Should show 15+ framework files
git status               # Should show clean working tree
launchctl list | grep claude.backup  # Should show 3 backup services

# Review current development
gh issue list            # See active development issues
git branch -a           # See available feature branches
```

### Architecture at a Glance
```
SuperClaude Framework v2.0
├── Entry Point: CLAUDE.md (@module loader pattern)
├── Commands: 16 specialized commands with wave orchestration
├── Personas: 11 AI specialists with auto-activation
├── MCP Servers: Context7, Sequential, Magic, Playwright
├── Quality Gates: 8-step validation pipeline
└── Documentation: Comprehensive technical and strategic docs
```

---

## 📁 File System Structure

### Core Framework Files
```
~/.claude/
├── CLAUDE.md                    # Entry point - @module loader
├── COMMANDS.md                  # 16-command execution framework
├── FLAGS.md                     # Flag system and auto-activation
├── PERSONAS.md                  # 11 AI specialist behaviors
├── ORCHESTRATOR.md              # Intelligent routing and quality gates
├── MCP.md                       # External service integration
├── PRINCIPLES.md                # Core development principles
├── RULES.md                     # Actionable operational rules
├── REGRESSION_PREVENTION.md     # Anti-regression protocols
├── MODES.md                     # Operational modes reference
├── PATTERN_EXTRACTION.md        # Pattern evolution system
└── [Additional framework files]
```

### Documentation Files
```
├── README.md                    # Quick start and overview
├── ARCHITECTURE.md              # Technical design documentation
├── SYSTEM_STATE.md              # Comprehensive system status
├── ROADMAP.md                   # Strategic planning v2.1-3.0+
├── CHANGELOG.md                 # Version history and lessons
├── PROJECT_STATUS.md            # Executive summary
├── DEVELOPER_GUIDE.md           # This file
├── GIT_CONFIG.md                # Repository configuration
└── RETIREMENT_SUMMARY.md        # Memory management v1 lessons
```

### Development Structure
```
├── scripts/                     # Utility scripts
│   ├── evolution-report.sh      # Pattern extraction reporting
│   ├── extract-local-patterns.sh # Local pattern extraction
│   └── session-context.sh       # Session management
├── engineering/                 # Development tools
│   ├── deploy-to-project.sh     # Project deployment
│   ├── setup.sh                 # System setup
│   └── test-harness.sh          # Testing framework
└── commands/                    # Command implementations
    └── sc/                      # SuperClaude commands
```

### Excluded Directories (Not in Git)
```
├── backups/                     # Conversation backups (105MB+)
├── projects/                    # Project-specific data (100MB+)
├── todos/                       # Task management data
├── shell-snapshots/             # Shell state snapshots
└── history/                     # Conversation history
```

---

## 🛠️ Development Workflow

### Branch Strategy
```bash
# Main branch: Production-ready code
git checkout main

# Feature branches: All development work
git checkout feature/shell-cleanup-verification    # Issue #1
git checkout feature/log-rotation                  # Issue #2  
git checkout feature/pattern-extraction-completion # Issue #3

# Create new feature branch
git checkout -b feature/your-feature-name
git push --set-upstream origin feature/your-feature-name
```

### Commit Standards
```bash
# Commit message format
git commit -m "Component: Description of change

Detailed explanation of what changed and why.
Include any breaking changes or migration notes.

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Quality Gates (Required)
Before any merge to main, ensure all components pass:
1. **Syntax validation** - Language parsers + Context7
2. **Type checking** - Sequential analysis + suggestions
3. **Linting** - Context7 rules + quality analysis  
4. **Security scanning** - Sequential + vulnerability assessment
5. **Testing** - Playwright E2E + ≥80% unit coverage
6. **Performance validation** - Sequential + benchmarking
7. **Documentation** - Context7 patterns + completeness
8. **Integration testing** - Playwright + deployment validation

---

## 🏗️ Architecture Deep Dive

### Module Loading Pattern
The system uses a declarative module loading pattern via `CLAUDE.md`:

```markdown
# CLAUDE.md
@COMMANDS.md
@FLAGS.md  
@PERSONAS.md
@ORCHESTRATOR.md
@MCP.md
# ... additional modules
```

**Benefits**:
- Clean dependency management
- Easy module addition/removal
- Clear loading order
- No circular dependencies

### Command Execution Pipeline
```
User Input → Command Parser → Orchestrator Analysis →
Persona Selection → MCP Coordination → Tool Execution →
Quality Gates → Response Generation → User Output
```

### Wave Orchestration
For complex operations (complexity ≥0.7 + files >20 + operation_types >2):
```
Stage 1: Analysis → Comprehensive understanding
Stage 2: Planning → Strategic approach  
Stage 3: Implementation → Coordinated execution
Stage 4: Validation → Quality assurance
Stage 5: Optimization → Performance tuning
```

### Persona Auto-Activation
Multi-factor scoring system:
- **Keyword Matching**: 30% weight
- **Context Analysis**: 40% weight  
- **User History**: 20% weight
- **Performance Metrics**: 10% weight

---

## 🔌 Integration Points

### MCP Server Integration
```yaml
# Server selection matrix
Context7: documentation, library research, patterns
Sequential: complex analysis, multi-step reasoning, debugging  
Magic: UI component generation, design systems
Playwright: browser automation, E2E testing, performance
```

### Tool Coordination
```yaml
# Tool usage patterns
Read: File analysis, understanding existing code
Write: New file creation, documentation generation
Edit/MultiEdit: Existing code modification, refactoring
Bash: System operations, testing, deployment
Grep/Glob: Search operations, file discovery
TodoWrite: Task management and progress tracking
```

---

## 🐛 Current Development Status

### Active Issues (GitHub Tracked)
1. **Shell Integration Cleanup Verification** (#1)
   - **Branch**: `feature/shell-cleanup-verification`
   - **Priority**: Critical
   - **Status**: Ready for development
   - **Tasks**: Systematic verification of memory management v1 removal

2. **LaunchAgent Log Rotation Strategy** (#2)
   - **Branch**: `feature/log-rotation`  
   - **Priority**: Medium
   - **Status**: Ready for development
   - **Tasks**: Implement automated log management

3. **Complete Pattern Extraction System** (#3)
   - **Branch**: `feature/pattern-extraction-completion`
   - **Priority**: High
   - **Status**: 90% complete
   - **Tasks**: Cross-project suggestions, automatic validation

### Development Milestones
- **v2.1** (Oct 2025): Bug fixes and pattern completion
- **v2.5** (Dec 2025): Performance analytics and monitoring  
- **v3.0** (Mar 2026): IDE integration and team collaboration

---

## 🧪 Testing Strategy

### Testing Levels
```yaml
Unit Tests:
  - Individual component functionality
  - Persona activation logic
  - Command parsing and validation
  - Quality gate validation
  
Integration Tests:
  - MCP server coordination
  - Tool execution workflows
  - Wave orchestration flows
  - End-to-end command execution

System Tests:
  - Full framework integration
  - Performance benchmarking
  - Error handling and recovery
  - Security validation
```

### Testing Tools
- **Playwright**: E2E testing, browser automation
- **Quality Gates**: Comprehensive validation pipeline
- **MCP Servers**: Real service integration testing
- **Bash Scripts**: System integration testing

---

## 📝 Documentation Standards

### Documentation Types
1. **Inline Documentation**: Code comments and docstrings
2. **Technical Documentation**: Architecture, APIs, integration guides
3. **User Documentation**: Getting started, tutorials, examples
4. **Strategic Documentation**: Roadmaps, project status, decisions

### Documentation Principles
- **Evidence-Based**: All claims supported by data or examples
- **User-Focused**: Written for the intended audience
- **Maintainable**: Easy to update as system evolves
- **Comprehensive**: Covers all aspects needed for success

---

## 🔒 Security & Privacy

### Data Protection
```yaml
Sensitive Data (Excluded from Git):
  - Conversation files and transcripts
  - User-specific backup data
  - Local configuration overrides
  - Runtime state and session data

Framework Data (Version Controlled):
  - Core framework files (.md configuration)
  - Scripts and utilities
  - Documentation and guides
  - Development tools and templates
```

### Security Practices
- **No Automatic Execution**: All operations require explicit invocation
- **Input Validation**: All user input sanitized and validated
- **Least Privilege**: Operations run with minimal required permissions
- **Audit Trail**: Operations logged for review and debugging

---

## 🎯 Contributing Guidelines

### Before You Start
1. **Read the Documentation**: Understand architecture and principles
2. **Check Issues**: See if your idea is already being worked on
3. **Follow Patterns**: Study existing code for consistency
4. **Test Thoroughly**: Ensure quality gates pass

### Contribution Process
```bash
# 1. Create feature branch
git checkout -b feature/your-contribution

# 2. Make changes following patterns
# 3. Test thoroughly (quality gates)
# 4. Update documentation as needed
# 5. Commit with proper message format

# 6. Push and create pull request
git push --set-upstream origin feature/your-contribution
gh pr create --title "Your Feature" --body "Description..."
```

### Code Standards
- **Follow Existing Patterns**: Study COMMANDS.md, PERSONAS.md structure
- **Maintain Simplicity**: Don't over-engineer (lesson from v1)
- **User Control**: No automatic behaviors without explicit user request
- **Quality Gates**: All contributions must pass validation pipeline

---

## 🆘 Troubleshooting

### Common Issues
```yaml
Framework Not Loading:
  - Check CLAUDE.md module references
  - Verify all .md files present (should be 15+)
  - Ensure proper @module syntax

Commands Not Working:
  - Verify COMMANDS.md structure
  - Check persona auto-activation patterns
  - Validate MCP server connectivity

Performance Issues:
  - Check wave orchestration triggers
  - Verify MCP server response times
  - Monitor quality gate execution times

Git Repository Issues:
  - Ensure GPG signing disabled
  - Check .gitignore excludes data directories
  - Verify private repository access
```

### Debug Commands
```bash
# System health check
cd ~/.claude && ls *.md | wc -l && git status

# Check MCP servers
# (MCP-specific commands depend on server implementations)

# Review recent activity
git log --oneline -10
gh issue list --limit 5

# Pattern extraction status
./scripts/evolution-report.sh dashboard
```

---

## 📚 Additional Resources

### Key Documentation Files
- **ARCHITECTURE.md**: Technical design deep dive
- **SYSTEM_STATE.md**: Comprehensive current status
- **REGRESSION_PREVENTION.md**: Critical protocols for avoiding past mistakes
- **PROJECT_STATUS.md**: Executive summary for decision makers

### External References
- **Repository**: https://github.com/juanandresgs/claude-system (Private)
- **Issues**: Track development progress and report bugs
- **Claude Code**: Integration platform and execution environment

### Learning Path
1. Start with **README.md** for overview
2. Read **ARCHITECTURE.md** for technical understanding
3. Review **SYSTEM_STATE.md** for current capabilities  
4. Study **ROADMAP.md** for future direction
5. Follow **DEVELOPER_GUIDE.md** (this file) for contribution

---

## 🎓 Lessons from Version History

### What We Learned (v1.0 → v2.0 Evolution)
**From Over-Engineering to Simplicity**:
- Shell function overrides (cd()) caused workflow interference
- Background monitoring added complexity without proportional value
- Automatic triggers frustrated users who wanted control
- Complex state management made debugging difficult

**Core Principles That Work**:
- **User Control**: Manual activation preferred over automatic
- **Simplicity**: Simple tools are more maintainable than complex ones
- **Modularity**: Independent components fail gracefully
- **Quality Gates**: Systematic validation prevents regressions
- **Documentation**: Comprehensive docs enable success

### Success Patterns
- **Evidence-Based Decisions**: All choices backed by data or clear reasoning
- **Incremental Development**: Build and test incrementally
- **User Feedback Integration**: Listen to user needs and frustrations
- **Quality Focus**: Maintain high standards throughout development

---

*This developer guide provides comprehensive information for contributing to the Claude System. For additional questions or clarification, review the extensive documentation in the repository or create a GitHub issue for discussion.*

**Last Updated**: September 2, 2025  
**Version**: 2.0  
**Status**: Production Ready with Active Development