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

### Tools
- ``Tool``
- ``AnyJSONTool``

### Memory and Sessions
- ``Memory``
- ``Session``

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
