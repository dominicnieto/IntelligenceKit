# ``Swarm``

A Swift framework for building agents and multi-agent workflows.

## Overview

Swarm provides type-safe agents with native tool calling, composable workflows
with crash recovery, and strict concurrency throughout. Agents run against any
``InferenceProvider`` — cloud (Anthropic, OpenAI, etc.) or on-device (Apple
Foundation Models, MLX).

## Topics

### Essentials
- ``Agent``
- ``AgentConfiguration``
- ``AgentResult``

### Workflows
- ``Workflow``
- ``Workflow/MergeStrategy``
- <doc:WorkflowComposition>

### Tools
- ``Tool``
- ``AnyJSONTool``
- ``FunctionTool``
- ``ToolParameter``
- ``ToolSchema``
- ``ToolRegistry``
- <doc:ToolAuthoring>

### Memory and Sessions
- ``Memory``
- ``ConversationMemory``
- ``SlidingWindowMemory``
- ``SummaryMemory``
- ``HybridMemory``
- ``PersistentMemory``
- ``VectorMemory``
- ``MemoryMessage``
- ``Session``
- <doc:MemoryAndSessions>

### Guardrails
- ``InputGuardrail``
- ``OutputGuardrail``
- ``GuardrailRunner``

### Errors
- ``AgentError``
- ``GuardrailError``
- ``WorkflowError``
- <doc:ErrorHandling>

### Configuration
- ``Swarm``
