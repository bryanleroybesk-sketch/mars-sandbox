# A.V.A — Mars Sandbox

A stylized isometric Mars colony where five AI executive agents (CEO, CMO, Creative Director, Operator, Analyst) live, work, meet and hang out. Everything runs locally: **Godot 4** renders the colony, and a **FastAPI + Ollama/Qwen** engine on your Mac turns natural-language commands into agent actions.

```
 You ──POST /command──▶ agent_bridge.py ──Ollama (Qwen)──▶ validated JSON
                              │   ▲
                   WebSocket  │   │  telemetry + review_request
                   /ws/godot  ▼   │
                         agent_bridge.gd ──▶ MarsWorld.dispatch_task()
                                                │
                                         MarsAgent state machine
                                                │ reaches Review Terminal
                                                ▼
                         Mac `say` voice prompt ──▶ you ──POST /review──▶ approve / redo
```

## Files

| File | Attach to / run | Role |
|---|---|---|
| `mars_world.gd` | root `Node3D` (main.tscn) | Environment, isometric camera, hub `Marker3D` anchors, navmesh bake, agent roster, meeting orchestration |
| `mars_agent.gd` | `CharacterBody3D` (auto-spawned) | State machine (IDLE / WORKING / MEETING / SOCIALIZING / AWAITING_REVIEW), NavigationAgent3D steering and RVO avoidance, needs, animation hooks |
| `agent_bridge.gd` | `Node` child of the world | WebSocket client with auto-reconnect; routes backend payloads to agents; sends the review safety hook out |
| `agent_bridge.py` | `python agent_bridge.py` | FastAPI engine on :8000, Ollama/Qwen router with keyword fallback, WebSocket hub, voice prompt, review gate |
| `project.godot`, `main.tscn` | — | Minimal runnable project (Godot 4.3+, tested on 4.4.1) |

## Quick start

```bash
# 1. Backend (macOS)
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
ollama pull qwen2.5:7b-instruct          # any Qwen tag works: export OLLAMA_MODEL=qwen3:8b
python agent_bridge.py                   # http://127.0.0.1:8000/docs

# 2. Godot: open this folder in Godot 4.3+ and press F5.
```

The Godot client connects to `ws://127.0.0.1:8000/ws/godot` automatically and keeps retrying, so you can start the two sides in either order. If Ollama is offline, commands still work through the deterministic keyword router.

### Driving the colony

```bash
# Natural language → Qwen → the right agent + hub
curl -X POST localhost:8000/command -H 'content-type: application/json' \
     -d '{"text": "Write an Instagram post announcing the new geodesic dome"}'

# Explicit agent (skips the LLM): "CMO task received: …" or "Analyst: …"
curl -X POST localhost:8000/command -H 'content-type: application/json' \
     -d '{"text": "CMO task received: Write Instagram Post"}'

# Direct, deterministic task
curl -X POST localhost:8000/task -H 'content-type: application/json' \
     -d '{"agent": "ANALYST", "task": "Weekly traffic report", "duration": 15}'

# Global meeting at the Command Center (auto-ends after 30 s)
curl -X POST localhost:8000/meeting -H 'content-type: application/json' \
     -d '{"action": "start", "duration": 30}'

# Human confirmation (the Mac says "CMO has finished … Do you approve?")
curl localhost:8000/reviews
curl -X POST localhost:8000/review -H 'content-type: application/json' \
     -d '{"agent": "CMO", "approved": false, "feedback": "More emojis"}'   # agent redoes it
```

Other endpoints: `GET /health`, `GET /agents` (live state), `GET /jobs/{id}` (for `"wait": false` commands), `GET /events?since=N` (polling fallback).

Godot debug hotkeys: **M** toggles a meeting, **T** sends a random test task, **R** rebakes the navmesh, **WASD** pans, **mouse wheel** zooms.

### Environment variables (`agent_bridge.py`)

| Var | Default | |
|---|---|---|
| `OLLAMA_URL` | `http://127.0.0.1:11434` | |
| `OLLAMA_MODEL` | `qwen2.5:7b-instruct` | any Qwen/Ollama tag |
| `OLLAMA_TIMEOUT` | `60` | seconds |
| `AVA_VOICE` / `AVA_VOICE_NAME` | `1` / system voice | macOS `say` prompts |
| `AVA_HOST` / `AVA_PORT` | `127.0.0.1` / `8000` | kept on localhost on purpose |

## Wire protocol (JSON over WebSocket)

**Python → Godot**

```jsonc
{"type":"task","task_id":"t-1a2b3c","agent":"CMO","task":"Write Instagram Post","building":"social_hub","duration":10,"priority":"normal"}
{"type":"meeting","action":"start","duration":30}      // or "end"
{"type":"review_result","agent":"CMO","task_id":"t-1a2b3c","approved":true,"feedback":""}
{"type":"snapshot_request"}   {"type":"ping"}
```

**Godot → Python**: `hello`, `snapshot`, `state` (on every state change), `task_started`, `task_completed`, `ack`, `pong`, and the safety hook:

```jsonc
{"type":"review_request","agent":"CMO","task":"Write Instagram Post","task_id":"t-1a2b3c","revisions":0,
 "prompt":"CMO has finished Write Instagram Post. Do you approve?"}
```

Inside Godot the same event is also emitted locally as `AgentBridge.human_review_requested(agent_name, task_title, payload)`, so you can hook UI or audio to it without the network.

## Agent behaviour

| State | Behaviour |
|---|---|
| **WORKING** | Paths to the task hub's `Entrance`, plays `working` until progress reaches the task duration (slower when energy is low). |
| **AWAITING_REVIEW** | Walks to the Review Terminal and emits `review_requested` (one time per attempt). Approved → done. Rejected → goes back and redoes the task. |
| **MEETING** | Interrupts any state. Each agent gets a ring slot around the Command Center, assigned by its current angle so nobody crosses the crowd. Agents stop inside `meeting_radius`, face the dome and play `talking`. `meeting_assembled` fires once everyone is in. Afterwards they resume their previous duty with task progress kept. |
| **IDLE** | Rests (energy regenerates) while boredom builds. |
| **SOCIALIZING** | Triggered by boredom or an idle timeout. The agent picks one of the nearest free agents and walks to a spot next to them. If that agent is already walking to a hangout, it heads for the same destination, so groups form. It talks while a partner is within `conversation_radius`, lingers, then drifts elsewhere or rests. |

Tasks that arrive while an agent is busy are queued. Agents on duty get a higher RVO `avoidance_priority` than socializers, so a working agent is never boxed in by a hangout circle. If an agent stops making progress toward its target, it re-plans and briefly slips through the crowd.

---

## Higgsfield asset pipeline: importing models and animations

### 1. Folder layout

```
res://assets/higgsfield/
  buildings/   command_center.glb, social_hub.glb, creative_lab.glb, comms_tower.glb,
               server_farm.glb, review_terminal.glb
  characters/  ceo.glb, cmo.glb, creative_director.glb, operator.glb, analyst.glb
  animations/  shared_humanoid_anims.glb   (optional shared library)
  materials/   extracted .tres materials
```

### 2. Export settings (Higgsfield / DCC side)

- **Prefer GLB (glTF 2.0).** Godot 4.3+ also imports FBX natively (ufbx), but glTF keeps materials, skins and animation names more reliably.
- **Scale**: 1 unit = 1 m. A character should be about 1.8 m tall. Hub footprints are in `HUB_LAYOUT` (the Command Center is about 10 m across).
- **Pivot** at the base centre (feet or foundation) at Y = 0.
- **Forward**: glTF characters face **+Z**, which is what `mars_agent.gd` assumes. If a rig faces another way, set `model_yaw_offset_deg` (for example 180) on the agent.
- **Animation clip names**: `idle`, `walk`, `working`, `talking` are ideal. Other names work too: the agent does a case-insensitive "contains" search (`Armature|Walk_Cycle` still resolves), or you can remap them in the `animation_map` export.

### 3. Import settings in Godot (double-click the .glb, then Advanced Import)

**Buildings**
- Materials: *Extract* to `materials/`, then tune for the reference look: roughness 0.85–1.0, metallic 0, white hull `#EBE6DC`, dark trim `#3B2B24`, terracotta accents `#B5532A`.
- Physics: leave off. `MarsWorld` adds a cylinder obstacle per hub (`footprint_radius`, `height` in `HUB_LAYOUT`) that the navmesh carves around. For irregular shapes (such as the long server rows), either add mesh-name suffixes `-colonly` in the DCC tool or add a `StaticBody3D` in an inherited scene, then untick `auto_obstacle_colliders`. Colliders anywhere under a hub anchor are picked up by the bake automatically.
- Generate LODs: on. Shadow meshes: on.

**Characters**
- Skeleton: in *Advanced Import → Skeleton3D*, assign a **BoneMap** with `SkeletonProfileHumanoid`. Retargeted rigs can then share one animation library.
- Animations: set **Loop Mode = Linear** for `idle`, `walk`, `working`, `talking`. (The agent also forces looping at runtime as a safety net.) Enable *Save to File* to export an `AnimationLibrary` `.res` if you want to share clips across characters.
- Root motion: not used. Movement comes from NavigationAgent3D, so strip or ignore root translation to avoid sliding.

### 4. Wrap in inherited scenes (recommended)

Right-click the `.glb` and choose **New Inherited Scene**. Save it as, for example, `cmo_character.tscn`. Here you can fix scale and offsets, swap materials, attach an `AnimationTree`, and add colliders without touching the source file. Re-importing a newer Higgsfield export keeps your tweaks.

### 5. Assign in the inspector

Select the **MarsWorld** root node:

- **Higgsfield Building Models**: drag each building scene into `command_center_model`, `social_hub_model`, and so on. The placeholder disappears and the model is instanced under `Hubs/<Hub>/Model`.
- **Higgsfield Character Models**: drag each character into `ceo_model`, `cmo_model`, and so on. It is instanced under the agent's `ModelRoot`. The first `AnimationPlayer` found inside becomes the animation driver.
- To move a hub, create `NavigationRegion3D/Hubs/<NodeName>` `Marker3D` nodes in the editor. Existing markers override the default layout.
- After changing buildings at runtime, call `await world.rebake_navigation()`, or press **R**.

### 6. Checklist per new asset

- [ ] Base pivot at Y = 0, real-world metres
- [ ] Character faces +Z (or `model_yaw_offset_deg` set)
- [ ] Clips named or mapped: idle / walk / working / talking, looping
- [ ] Building footprint fits the hub's `footprint_radius` (or has its own colliders)
- [ ] Matte materials (roughness ≥ 0.85, metallic 0) to match the diorama look
