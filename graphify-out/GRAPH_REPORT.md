# Graph Report - mars-sandbox  (2026-10-13)

## Corpus Check
- 3 files · ~4,811 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 11 file(s) not represented in the graph (top: .gd 4, .uid 4, (none) 1)

## Summary
- 128 nodes · 207 edges · 10 communities (7 shown, 3 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 4 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4cf8a257`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- agent_bridge.py
- RoutedIntent
- Higgsfield asset pipeline: importing models and animations
- post_task
- CommandEngine
- Any
- GodotHub
- post_command
- Mars Sandbox: code graph
- VoiceAnnouncer

## God Nodes (most connected - your core abstractions)
1. `RoutedIntent` - 11 edges
2. `GodotHub` - 9 edges
3. `AgentRole` - 8 edges
4. `normalize_role()` - 8 edges
5. `OllamaRouter` - 8 edges
6. `CommandEngine` - 8 edges
7. `lifespan()` - 8 edges
8. `post_command()` - 7 edges
9. `post_task()` - 7 edges
10. `Higgsfield asset pipeline: importing models and animations` - 7 edges

## Surprising Connections (you probably didn't know these)
- `AgentRole` --inherits--> `Enum`  [EXTRACTED]
  agent_bridge.py →   _Bridges community 1 → community 0_
- `post_task()` --calls--> `AgentRole`  [EXTRACTED]
  agent_bridge.py → agent_bridge.py  _Bridges community 1 → community 3_
- `CommandRequest` --inherits--> `BaseModel`  [EXTRACTED]
  agent_bridge.py →   _Bridges community 7 → community 3_
- `intent_to_payload()` --references--> `RoutedIntent`  [EXTRACTED]
  agent_bridge.py → agent_bridge.py  _Bridges community 1 → community 5_
- `post_command()` --references--> `Any`  [EXTRACTED]
  agent_bridge.py →   _Bridges community 5 → community 7_

## Import Cycles
- None detected.

## Communities (10 total, 3 thin omitted)

### Community 1 - "RoutedIntent"
Cohesion: 0.16
Nodes (7): AgentRole, explicit_route(), _extract_json(), keyword_route(), normalize_role(), RoutedIntent, _short_title()

### Community 2 - "Higgsfield asset pipeline: importing models and animations"
Cohesion: 0.12
Nodes (16): 1. Folder layout, 2. Export settings (Higgsfield / DCC side), 3. Import settings in Godot (double-click the .glb, then Advanced Import), 4. Wrap in inherited scenes (recommended), 5. Assign in the inspector, 6. Checklist per new asset, A.V.A — Mars Sandbox, Agent behaviour (+8 more)

### Community 3 - "post_task"
Cohesion: 0.15
Nodes (6): DirectTaskRequest, MeetingRequest, post_meeting(), post_review(), post_task(), ReviewDecision

### Community 4 - "CommandEngine"
Cohesion: 0.20
Nodes (3): CommandEngine, lifespan(), OllamaRouter

### Community 5 - "Any"
Cohesion: 0.25
Nodes (6): get_agents(), get_events(), get_job(), get_reviews(), health(), intent_to_payload()

### Community 7 - "post_command"
Cohesion: 0.29
Nodes (3): CommandRequest, Job, post_command()

### Community 8 - "Mars Sandbox: code graph"
Cohesion: 0.29
Nodes (6): agent_bridge.py, Agent state machine (MarsAgent), Godot class and signal flow, Mars Sandbox: code graph, Modules, Sizes

## Knowledge Gaps
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GodotHub` connect `GodotHub` to `agent_bridge.py`, `CommandEngine`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Should `agent_bridge.py` be split into smaller, more focused modules?**
  _Cohesion score 0.11052631578947368 - nodes in this community are weakly interconnected._
- **Why does `OllamaRouter` connect `CommandEngine` to `agent_bridge.py`, `RoutedIntent`?**
  _High betweenness centrality (0.055) - this node is a cross-community bridge._
- **Should `Higgsfield asset pipeline: importing models and animations` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Why does `RoutedIntent` connect `RoutedIntent` to `agent_bridge.py`, `post_task`, `Any`?**
  _High betweenness centrality (0.053) - this node is a cross-community bridge._