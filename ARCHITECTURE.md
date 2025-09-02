# Claude System Architecture

**Technical Design Documentation**  
Version 2.0 | Post-Retirement Architecture

---

## Architectural Overview

The Claude system follows a **modular, declarative architecture** where components are:
- **Loosely coupled** - Components communicate through well-defined interfaces
- **Highly cohesive** - Each module has a single, clear responsibility
- **Stateless** - No persistent session state between invocations
- **User-controlled** - All operations require explicit invocation

```
┌─────────────────────────────────────────────────────────┐
│                    User Interface                        │
│                  (Claude Code CLI)                       │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                   CLAUDE.md Entry Point                  │
│                 (Module Loader & Router)                 │
└─────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┴───────────────────┐
        ▼                                       ▼
┌──────────────┐                       ┌──────────────┐
│   Commands   │                       │    Flags     │
│   System     │                       │   System     │
└──────────────┘                       └──────────────┘
        │                                       │
        ▼                                       ▼
┌──────────────┐                       ┌──────────────┐
│ Orchestrator │◄──────────────────────│   Personas   │
│   (Router)   │                       │   (11 AIs)   │
└──────────────┘                       └──────────────┘
        │
        ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Quality      │     │     MCP      │     │    Wave      │
│   Gates      │◄────│   Servers    │────►│ Orchestration│
└──────────────┘     └──────────────┘     └──────────────┘
```

## Core Design Patterns

### 1. Module Loader Pattern

**Implementation**: `CLAUDE.md` as entry point with `@module` syntax

```markdown
# CLAUDE.md
@COMMANDS.md
@FLAGS.md
@PERSONAS.md
...
```

**Benefits**:
- Clean dependency management
- Easy module addition/removal
- Clear loading order
- No circular dependencies

### 2. Command Pattern with Wave Orchestration

**Structure**:
```yaml
command:
  name: "/analyze"
  category: "Analysis & Investigation"
  wave_enabled: true
  personas: [Analyzer, Architect, Security]
  mcp_servers: [Sequential, Context7]
  quality_gates: 8
```

**Wave Orchestration Logic**:
```
IF complexity >= 0.7 AND files > 20 AND operation_types > 2:
    ENABLE wave_mode
    ORCHESTRATE multi_stage_execution
    APPLY compound_intelligence
```

### 3. Persona Strategy Pattern

**Selection Algorithm**:
```python
def select_persona(context):
    scores = {}
    for persona in available_personas:
        scores[persona] = calculate_score(
            keyword_match=0.3,
            context_analysis=0.4,
            user_history=0.2,
            performance_metrics=0.1
        )
    return max(scores, key=scores.get)
```

**Auto-Activation Triggers**:
- Keywords in user request
- Project type detection
- Complexity assessment
- Historical success patterns

### 4. Quality Gate Pipeline

**8-Step Validation Architecture**:
```
Input → Syntax → Type → Lint → Security → Test → Performance → Documentation → Integration → Output
  ↓       ↓       ↓      ↓        ↓        ↓          ↓              ↓            ↓
 Fail    Fail    Fail   Fail     Fail     Fail       Fail          Fail         Fail
  ↓       ↓       ↓      ↓        ↓        ↓          ↓              ↓            ↓
 Abort   Abort   Abort  Abort    Abort    Abort      Abort         Abort        Abort
```

**Implementation**: Each gate can halt execution with detailed feedback

### 5. MCP Server Abstraction

**Server Integration Layer**:
```typescript
interface MCPServer {
    name: string;
    capabilities: string[];
    activate(context: Context): boolean;
    execute(request: Request): Response;
    fallback(): MCPServer | null;
}
```

**Available Servers**:
- **Context7**: Documentation, library research
- **Sequential**: Multi-step analysis, complex reasoning
- **Magic**: UI component generation
- **Playwright**: Browser automation, E2E testing

**Coordination Strategy**:
1. Task analysis determines required capabilities
2. Server selection based on capability matching
3. Load balancing across available servers
4. Automatic fallback on failure

## Component Architecture

### Commands Module

**Design**: Declarative command definitions with metadata-driven execution

```yaml
command_structure:
  metadata:
    name: string
    category: string
    wave_enabled: boolean
    performance_profile: optimization|standard|complex
  
  execution:
    pre_validation: quality_gates[0-2]
    main_execution: orchestrated_operation
    post_validation: quality_gates[3-7]
    
  integration:
    personas: auto_selected_based_on_context
    mcp_servers: capability_based_selection
    tools: [Read, Write, Edit, Bash, etc.]
```

### Personas Module

**Architecture**: Independent AI personalities with specialized behavior

```yaml
persona_structure:
  identity:
    name: string
    domain: string
    priority_hierarchy: ordered_list
    
  capabilities:
    core_principles: list
    decision_frameworks: list
    quality_standards: dict
    
  integration:
    mcp_preferences: {primary, secondary, avoided}
    command_optimization: specialized_approaches
    auto_activation_triggers: pattern_list
```

**Cross-Persona Collaboration**:
- Primary persona leads decision-making
- Consulting personas provide specialized input
- Validation personas review for quality
- Seamless handoff between expertise boundaries

### Orchestrator Module

**Purpose**: Intelligent routing and quality enforcement

**Key Components**:
1. **Detection Engine**: Analyzes requests for intent and complexity
2. **Routing Intelligence**: Maps patterns to optimal tool combinations
3. **Quality Gates**: Enforces validation at each step
4. **Performance Optimization**: Resource management and batching

**Routing Table Example**:
```yaml
pattern: "analyze architecture"
complexity: complex
domain: infrastructure
auto_activates:
  - architect persona
  - --ultrathink flag
  - Sequential MCP
confidence: 95%
```

### Backup System (Simplified)

**Current Implementation**:
```bash
#!/bin/bash
# simple_backup.sh - Minimal conversation backup
BACKUP_TYPE="${1:-daily}"
BACKUP_DIR="$HOME/.claude/backups/$BACKUP_TYPE"

# Simple collection without state management
find "$CLAUDE_PROJECTS" -name "*.jsonl" -exec cp {} "$BACKUP_DIR/" \;
```

**Design Principles**:
- Single responsibility (backup only)
- No state management
- No shell integration
- LaunchAgent automation

## Integration Points

### 1. Claude Code CLI Integration

**Method**: Module loading via CLAUDE.md reference
**Interface**: Command execution through CLI
**Feedback**: Structured output with quality metrics

### 2. File System Integration

**Principles**:
- Read-only by default
- Explicit write operations
- No automatic file watchers
- Clear directory boundaries

### 3. Shell Environment

**Current State**: NO shell integration
**Previous Issues**: cd() override, automatic triggers, state persistence
**Resolution**: Complete removal of shell hooks

### 4. External Services (MCP)

**Integration Pattern**:
```
Claude → Orchestrator → MCP Selector → Server → Response
                ↓                         ↓
            Fallback ←──── Failure ────────┘
```

## Data Flow Architecture

### Command Execution Flow

```
1. User Input
   ↓
2. Command Parser → Extract command, flags, arguments
   ↓
3. Orchestrator → Analyze complexity, select strategy
   ↓
4. Persona Selection → Auto-activate appropriate specialist
   ↓
5. MCP Coordination → Select and coordinate servers
   ↓
6. Tool Execution → Read, Write, Edit, Bash operations
   ↓
7. Quality Gates → Validate at each step
   ↓
8. Response Generation → Structured output with insights
```

### Wave Orchestration Flow

```
1. Complexity Assessment → Score > 0.7?
   ↓ Yes
2. Wave Initialization → Plan multi-stage execution
   ↓
3. Stage 1: Analysis → Comprehensive understanding
   ↓
4. Stage 2: Planning → Strategic approach
   ↓
5. Stage 3: Implementation → Coordinated execution
   ↓
6. Stage 4: Validation → Quality assurance
   ↓
7. Stage 5: Optimization → Performance tuning
```

## Error Handling & Recovery

### Error Categories

1. **Input Errors**: Invalid commands, missing arguments
2. **Execution Errors**: Tool failures, permission issues
3. **Integration Errors**: MCP server unavailable, network issues
4. **Quality Failures**: Validation gate failures
5. **System Errors**: Resource exhaustion, unexpected states

### Recovery Strategies

```yaml
error_recovery:
  input_errors:
    strategy: prompt_for_clarification
    fallback: suggest_similar_commands
    
  execution_errors:
    strategy: retry_with_backoff
    fallback: alternative_tool_selection
    
  integration_errors:
    strategy: use_fallback_server
    fallback: local_execution_only
    
  quality_failures:
    strategy: provide_detailed_feedback
    fallback: rollback_changes
    
  system_errors:
    strategy: graceful_degradation
    fallback: emergency_shutdown
```

## Performance Considerations

### Optimization Strategies

1. **Lazy Loading**: Modules loaded only when needed
2. **Caching**: MCP responses cached within session
3. **Parallel Execution**: Independent operations run concurrently
4. **Resource Limits**: Token usage monitoring and limits
5. **Early Termination**: Fail fast on quality gate violations

### Performance Targets

```yaml
targets:
  command_response: <100ms for standard operations
  wave_orchestration: <10s for complex multi-stage
  quality_validation: <500ms per gate
  mcp_coordination: <2s including fallback
  total_operation: <30s for most complex tasks
```

## Security Architecture

### Security Principles

1. **Least Privilege**: Operations run with minimal required permissions
2. **Input Validation**: All user input sanitized and validated
3. **No Automatic Execution**: All operations require explicit invocation
4. **Audit Trail**: Operations logged for review
5. **Sandboxing**: External operations isolated where possible

### Security Gates

- **Gate 4**: Security scanning with Sequential MCP
- **Vulnerability Assessment**: OWASP compliance checking
- **Dependency Scanning**: Known vulnerability detection
- **Access Control**: File system permission validation
- **Secret Detection**: Prevent credential exposure

## Extensibility

### Adding New Commands

1. Create command definition in COMMANDS.md
2. Define wave orchestration requirements
3. Specify persona preferences
4. Add to orchestrator routing table
5. Implement quality gate requirements

### Adding New Personas

1. Define persona in PERSONAS.md
2. Specify domain and capabilities
3. Set MCP server preferences
4. Define auto-activation triggers
5. Add cross-persona collaboration rules

### Adding MCP Servers

1. Implement MCPServer interface
2. Define capabilities and use cases
3. Add to MCP.md configuration
4. Update orchestrator selection logic
5. Implement fallback strategies

## Retired Architecture (Lessons Learned)

### What Was Removed

```
REMOVED: Automatic Memory Management System
├── Complex shell integration (cd() override)
├── Background LaunchAgent monitoring
├── Git hooks for auto-extraction  
├── Session state persistence
└── Deep Claude Code integration

MOVED TO: ~/.claude-retired/memory-management-v1/
```

### Why It Failed

1. **Over-Engineering**: Too many interconnected components
2. **Invasive Integration**: Hijacked core shell functions
3. **Automatic Behavior**: Users lost control over activation
4. **State Management**: Persistent files created complexity
5. **Debugging Difficulty**: Complex interactions hard to trace

### Key Lessons

- **Simplicity Wins**: Simple tools are more maintainable
- **User Control**: Manual activation preferred
- **Independence**: Components should work in isolation
- **No Magic**: Explicit behavior over automatic triggers
- **Respect the Shell**: Don't override basic functions

## Future Architecture Considerations

### Recommended Patterns

1. **Plugin Architecture**: Isolated, optional components
2. **Event-Driven**: Publish-subscribe for loose coupling
3. **Configuration as Code**: Declarative system configuration
4. **Immutable Operations**: No side effects where possible
5. **Observability First**: Built-in monitoring and metrics

### Not Recommended

1. **Shell Function Overrides**: Respect standard behavior
2. **Automatic Triggers**: Require explicit invocation
3. **Complex State**: Keep operations stateless
4. **Deep Integration**: Maintain clear boundaries
5. **Background Processes**: Avoid unnecessary daemons

---

*This architecture prioritizes simplicity, modularity, and user control while providing powerful AI-enhanced development capabilities through the SuperClaude framework.*