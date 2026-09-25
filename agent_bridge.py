#!/usr/bin/env python3
"""
A.V.A "Mars Sandbox" — Local backend engine (FastAPI, runs on your Mac).

    User / tools ──HTTP POST──▶  agent_bridge.py  ──WebSocket JSON──▶  Godot
                                   │    ▲                                 │
                                   ▼    │                                 │
                            Ollama (Qwen) router        review_request ◀──┘
                                                          │
                                              macOS `say` voice prompt
                                                          │
                              POST /review  ◀── human confirmation

Responsibilities
----------------
1. HTTP API on 127.0.0.1:8000 for commands ("Write an Instagram post about
   the launch"), direct tasks, meetings and review decisions.
2. A background job worker that sends free-text commands to a local Ollama
   model (Qwen by default). The model must answer in a strict JSON schema,
   which is validated with Pydantic and turned into a clean Godot payload.
   If Ollama is down or answers badly, a deterministic keyword router takes
   over, so the sandbox keeps working.
3. A WebSocket hub (/ws/godot) that pushes payloads to the Godot client
   (agent_bridge.gd) and receives agent telemetry back. GET /events is a
   polling fallback for clients that can't hold a socket open.
4. The human-in-the-loop safety gate. When an agent reaches the Review
   Terminal, Godot sends `review_request`. The engine speaks it aloud through
   the Mac audio output and keeps it pending until POST /review arrives.

Run
---
    pip install -r requirements.txt
    ollama pull qwen2.5:7b-instruct        # or: export OLLAMA_MODEL=qwen3:8b
    python agent_bridge.py                 # serves http://127.0.0.1:8000

Try it
------
    curl -X POST localhost:8000/command -H 'content-type: application/json' \
         -d '{"text": "Write an Instagram post announcing the new dome"}'
    curl -X POST localhost:8000/meeting -H 'content-type: application/json' \
         -d '{"action": "start", "duration": 30}'
    curl -X POST localhost:8000/review  -H 'content-type: application/json' \
         -d '{"agent": "CMO", "approved": true}'

Interactive docs: http://127.0.0.1:8000/docs
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import platform
import re
import shutil
import time
import uuid
from collections import deque
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Literal

import httpx
import uvicorn
from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field, ValidationError, field_validator

# =============================================================================
#  Configuration (environment variables with sane local defaults)
# =============================================================================
HOST = os.getenv("AVA_HOST", "127.0.0.1")
PORT = int(os.getenv("AVA_PORT", "8000"))
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:7b-instruct")
OLLAMA_TIMEOUT = float(os.getenv("OLLAMA_TIMEOUT", "60"))
# Speak review requests with macOS `say` ("0" disables it).
VOICE_ENABLED = os.getenv("AVA_VOICE", "1") == "1"
VOICE_NAME = os.getenv("AVA_VOICE_NAME", "")  # e.g. "Samantha"; empty = system default
WORKER_COUNT = int(os.getenv("AVA_WORKERS", "1"))  # >1 only if Ollama has spare capacity
EVENT_LOG_SIZE = 500

logging.basicConfig(
    level=os.getenv("AVA_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("ava.bridge")


# =============================================================================
#  Domain model (must mirror mars_world.gd AGENT_ROSTER / HUB_LAYOUT)
# =============================================================================
class AgentRole(str, Enum):
    CEO = "CEO"
    CMO = "CMO"
    CREATIVE_DIRECTOR = "CREATIVE_DIRECTOR"
    OPERATOR = "OPERATOR"
    ANALYST = "ANALYST"


class Hub(str, Enum):
    COMMAND_CENTER = "command_center"
    SOCIAL_HUB = "social_hub"
    CREATIVE_LAB = "creative_lab"
    COMMS_TOWER = "comms_tower"
    SERVER_FARM = "server_farm"


ROLE_HOME_HUB: dict[AgentRole, Hub] = {
    AgentRole.CEO: Hub.COMMAND_CENTER,
    AgentRole.CMO: Hub.SOCIAL_HUB,
    AgentRole.CREATIVE_DIRECTOR: Hub.CREATIVE_LAB,
    AgentRole.OPERATOR: Hub.COMMS_TOWER,
    AgentRole.ANALYST: Hub.SERVER_FARM,
}

ROLE_DESCRIPTIONS: dict[AgentRole, str] = {
    AgentRole.CEO: "strategy, planning, budgets, decisions, priorities, anything cross-functional",
    AgentRole.CMO: "marketing, social media posts (Instagram, TikTok, X, LinkedIn), campaigns, copywriting, community",
    AgentRole.CREATIVE_DIRECTOR: "visual design, logos, images, video concepts, 3D assets, branding, mockups",
    AgentRole.OPERATOR: "logistics, email, WhatsApp, messaging customers, scheduling, orders, follow-ups",
    AgentRole.ANALYST: "analytics, web traffic, metrics, KPIs, reports, SEO, dashboards, data questions",
}

# Loose names users (or the LLM) may type → canonical role.
ROLE_ALIASES: dict[str, AgentRole] = {
    "ceo": AgentRole.CEO, "boss": AgentRole.CEO,
    "cmo": AgentRole.CMO, "marketing": AgentRole.CMO,
    "creativedirector": AgentRole.CREATIVE_DIRECTOR, "creative": AgentRole.CREATIVE_DIRECTOR,
    "cd": AgentRole.CREATIVE_DIRECTOR, "designer": AgentRole.CREATIVE_DIRECTOR,
    "operator": AgentRole.OPERATOR, "ops": AgentRole.OPERATOR,
    "analyst": AgentRole.ANALYST, "analytics": AgentRole.ANALYST,
}


def normalize_role(value: str | AgentRole | None) -> AgentRole | None:
    """'Creative Director', 'creative_director', 'cd' → AgentRole.CREATIVE_DIRECTOR."""
    if value is None:
        return None
    if isinstance(value, AgentRole):
        return value
    key = re.sub(r"[\s_\-]", "", str(value)).lower()
    for role in AgentRole:
        if role.value.replace("_", "").lower() == key:
            return role
    return ROLE_ALIASES.get(key)


# =============================================================================
#  API schemas
# =============================================================================
class CommandRequest(BaseModel):
    """Free-text instruction routed through the Ollama/Qwen pipeline."""

    text: str = Field(..., min_length=1, max_length=4000, examples=["Write an Instagram post about our new dome"])
    agent_hint: AgentRole | None = Field(None, description="Force a specific agent (skips role selection).")
    wait: bool = Field(True, description="Block until routed. False returns 202 + job_id immediately.")


class DirectTaskRequest(BaseModel):
    """Deterministic task, no LLM involved."""

    agent: str
    task: str = Field(..., min_length=1, max_length=200)
    building: Hub | None = None
    duration: float | None = Field(None, gt=0, le=600)

    @field_validator("agent")
    @classmethod
    def _valid_agent(cls, v: str) -> str:
        role = normalize_role(v)
        if role is None:
            raise ValueError(f"unknown agent '{v}'")
        return role.value


class MeetingRequest(BaseModel):
    action: Literal["start", "end"] = "start"
    duration: float | None = Field(None, gt=0, le=3600, description="Auto-end after N seconds.")


class ReviewDecision(BaseModel):
    """Human verdict for a pending review (voice UI, CLI, Shortcuts …)."""

    agent: str
    approved: bool
    feedback: str = ""
    task_id: str | None = None


class RoutedIntent(BaseModel):
    """Strict structure the LLM must return. Also used by the keyword fallback."""

    intent: Literal["task", "meeting_start", "meeting_end"] = "task"
    agent: AgentRole = AgentRole.CEO
    task: str = Field("General task", max_length=120)
    building: Hub | None = None
    duration_sec: float = Field(10.0, ge=3.0, le=120.0)
    priority: Literal["low", "normal", "high"] = "normal"
    reasoning: str = Field("", max_length=400)

    @field_validator("agent", mode="before")
    @classmethod
    def _coerce_agent(cls, v: Any) -> Any:
        return normalize_role(v) or v

    @field_validator("task")
    @classmethod
    def _clean_task(cls, v: str) -> str:
        v = re.sub(r"\s+", " ", v).strip().strip('"').strip()
        return v[:120] or "General task"

    @field_validator("duration_sec", mode="before")
    @classmethod
    def _clamp_duration(cls, v: Any) -> float:
        try:
            return max(3.0, min(120.0, float(v)))
        except (TypeError, ValueError):
            return 10.0


# Hand-written, flat JSON schema for Ollama's structured output (`format`).
# Flat (no $ref/$defs) so every Ollama/llama.cpp version can compile it.
LLM_OUTPUT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "intent": {"type": "string", "enum": ["task", "meeting_start", "meeting_end"]},
        "agent": {"type": "string", "enum": [r.value for r in AgentRole]},
        "task": {"type": "string"},
        "building": {"type": "string", "enum": [h.value for h in Hub]},
        "duration_sec": {"type": "number"},
        "priority": {"type": "string", "enum": ["low", "normal", "high"]},
        "reasoning": {"type": "string"},
    },
    "required": ["intent", "agent", "task", "building", "duration_sec", "priority", "reasoning"],
}


def _build_system_prompt() -> str:
    roster = "\n".join(
        f"- {role.value} (works at {ROLE_HOME_HUB[role].value}): {desc}"
        for role, desc in ROLE_DESCRIPTIONS.items()
    )
    return f"""You are the dispatcher of A.V.A, a Mars colony of AI executive agents.
Route the user's instruction to exactly ONE agent and rewrite it as a short
task title (imperative, max 8 words, e.g. "Write Instagram launch post").

Agents:
{roster}

Rules:
- intent = "meeting_start" if the user wants everyone to gather / a meeting / a sync;
  "meeting_end" if they want to end or dismiss a meeting; otherwise "task".
- building is normally the chosen agent's own hub.
- duration_sec: 5-15 for quick tasks, 20-60 for substantial work.
- priority: "high" only if the user signals urgency.
- reasoning: one short sentence.
Respond with JSON only."""


SYSTEM_PROMPT = _build_system_prompt()


# =============================================================================
#  Ollama / Qwen routing pipeline
# =============================================================================
KEYWORD_ROUTES: list[tuple[AgentRole, re.Pattern[str]]] = [
    (AgentRole.CMO, re.compile(r"\b(instagram|insta|tiktok|tweet|twitter|linkedin|post|caption|campaign|marketing|social|influencer|hashtag|copy)\b", re.I)),
    (AgentRole.CREATIVE_DIRECTOR, re.compile(r"\b(design|logo|image|picture|video|render|mockup|brand(ing)?|illustrat\w*|3d|thumbnail|visual)\b", re.I)),
    (AgentRole.OPERATOR, re.compile(r"\b(e-?mail|whatsapp|message|reply|send|schedul\w*|calendar|logistics|order|ship\w*|invoice|call|follow[- ]?up)\b", re.I)),
    (AgentRole.ANALYST, re.compile(r"\b(analytics?|traffic|metrics?|kpis?|report|data|seo|dashboard|conversion|stats|numbers)\b", re.I)),
    (AgentRole.CEO, re.compile(r"\b(strategy|plan|budget|decide|decision|priorit\w*|roadmap|hire|vision)\b", re.I)),
]

# "CMO task received: Write Instagram Post" / "Analyst: pull weekly traffic"
EXPLICIT_PATTERN = re.compile(r"^\s*(?P<agent>[A-Za-z _-]{2,30}?)\s*(?:task\s+received)?\s*:\s*(?P<task>.+)$", re.I)
MEETING_START_PATTERN = re.compile(r"\b(meeting|gather|assemble|all hands|sync up|huddle)\b", re.I)
MEETING_END_PATTERN = re.compile(r"\b(end|stop|dismiss|finish|adjourn)\b.*\bmeeting\b|\bmeeting\b.*\b(over|end(ed)?|done)\b", re.I)


def _short_title(text: str, max_words: int = 8) -> str:
    words = re.sub(r"\s+", " ", text).strip().rstrip(".!?").split(" ")
    title = " ".join(words[:max_words])
    return title[:1].upper() + title[1:] if title else "General task"


def explicit_route(text: str) -> RoutedIntent | None:
    """Deterministic parse when the user already names the agent."""
    m = EXPLICIT_PATTERN.match(text)
    if not m:
        return None
    role = normalize_role(m.group("agent"))
    if role is None:
        return None
    return RoutedIntent(agent=role, task=_short_title(m.group("task")), building=ROLE_HOME_HUB[role],
                        reasoning="Agent named explicitly.")


def keyword_route(text: str, hint: AgentRole | None = None) -> RoutedIntent:
    """Offline fallback router: regex keywords → agent. Never fails."""
    if MEETING_END_PATTERN.search(text):
        return RoutedIntent(intent="meeting_end", reasoning="Keyword fallback: end meeting.")
    if MEETING_START_PATTERN.search(text):
        return RoutedIntent(intent="meeting_start", reasoning="Keyword fallback: meeting.")
    role = hint
    if role is None:
        # Pick the role with the most keyword hits; CEO is the default owner.
        scores = {r: len(p.findall(text)) for r, p in KEYWORD_ROUTES}
        best = max(scores, key=lambda r: scores[r])
        role = best if scores[best] > 0 else AgentRole.CEO
    return RoutedIntent(agent=role, task=_short_title(text), building=ROLE_HOME_HUB[role],
                        reasoning="Keyword fallback router.")


def _extract_json(content: str) -> str:
    """Strip Qwen3 <think> blocks and ```json fences; return the JSON object."""
    content = re.sub(r"<think>.*?</think>", "", content, flags=re.S).strip()
    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", content, flags=re.S)
    if fenced:
        return fenced.group(1)
    start, end = content.find("{"), content.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("no JSON object in model output")
    return content[start : end + 1]


class OllamaRouter:
    """Turns free text into a validated RoutedIntent via a local Qwen model."""

    def __init__(self, client: httpx.AsyncClient) -> None:
        self._client = client

    async def is_available(self) -> bool:
        try:
            r = await self._client.get(f"{OLLAMA_URL}/api/tags", timeout=3.0)
            return r.status_code == 200
        except httpx.HTTPError:
            return False

    async def route(self, text: str, hint: AgentRole | None = None) -> tuple[RoutedIntent, str]:
        """Returns (intent, source) where source ∈ {"explicit", "llm", "fallback"}."""
        if hint is None and (explicit := explicit_route(text)):
            return explicit, "explicit"
        try:
            intent = await self._ask_llm(text, hint)
            return intent, "llm"
        except (httpx.HTTPError, ValidationError, ValueError, KeyError, json.JSONDecodeError) as exc:
            log.warning("Ollama routing failed (%s: %s); using keyword fallback.", type(exc).__name__, exc)
            return keyword_route(text, hint), "fallback"

    async def _ask_llm(self, text: str, hint: AgentRole | None) -> RoutedIntent:
        user_msg = text if hint is None else f"[Assign to {hint.value}] {text}"
        body = {
            "model": OLLAMA_MODEL,
            "stream": False,
            "format": LLM_OUTPUT_SCHEMA,          # constrained JSON decoding
            "options": {"temperature": 0.1},
            "keep_alive": "10m",                   # keep Qwen warm between commands
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_msg},
            ],
        }
        started = time.perf_counter()
        r = await self._client.post(f"{OLLAMA_URL}/api/chat", json=body, timeout=OLLAMA_TIMEOUT)
        r.raise_for_status()
        content = r.json()["message"]["content"]
        intent = RoutedIntent.model_validate_json(_extract_json(content))
        if hint is not None:
            intent.agent = hint
        if intent.building is None:
            intent.building = ROLE_HOME_HUB[intent.agent]
        log.info("Qwen routed in %.1fs → %s: %s", time.perf_counter() - started, intent.agent.value, intent.task)
        return intent


def intent_to_payload(intent: RoutedIntent, task_id: str) -> dict[str, Any]:
    """Map a routed intent to the exact JSON agent_bridge.gd understands."""
    if intent.intent == "meeting_start":
        return {"type": "meeting", "action": "start", "duration": intent.duration_sec * 3}
    if intent.intent == "meeting_end":
        return {"type": "meeting", "action": "end"}
    return {
        "type": "task",
        "task_id": task_id,
        "agent": intent.agent.value,
        "task": intent.task,
        "building": (intent.building or ROLE_HOME_HUB[intent.agent]).value,
        "duration": intent.duration_sec,
        "priority": intent.priority,
    }


# =============================================================================
#  Godot connection hub (WebSocket push + polling log + telemetry cache)
# =============================================================================
class GodotHub:
    def __init__(self) -> None:
        self._sockets: set[WebSocket] = set()
        self._lock = asyncio.Lock()
        self._seq = 0
        self.events: deque[dict[str, Any]] = deque(maxlen=EVENT_LOG_SIZE)
        self.agent_states: dict[str, dict[str, Any]] = {}
        self.pending_reviews: dict[str, dict[str, Any]] = {}  # agent → review_request
        self.meeting_active = False

    @property
    def client_count(self) -> int:
        return len(self._sockets)

    async def attach(self, ws: WebSocket) -> None:
        await ws.accept()
        async with self._lock:
            self._sockets.add(ws)
        log.info("Godot client connected (%d total).", self.client_count)

    async def detach(self, ws: WebSocket) -> None:
        async with self._lock:
            self._sockets.discard(ws)
        log.info("Godot client disconnected (%d left).", self.client_count)

    async def broadcast(self, payload: dict[str, Any]) -> int:
        """Log the payload (for /events pollers) and push it to every socket."""
        self._seq += 1
        self.events.append({"seq": self._seq, "ts": time.time(), "payload": payload})
        if payload.get("type") == "meeting":
            self.meeting_active = payload.get("action") == "start"
        async with self._lock:
            sockets = list(self._sockets)
        delivered = 0
        for ws in sockets:
            try:
                await ws.send_json(payload)
                delivered += 1
            except Exception:  # noqa: BLE001 — a dead socket must not break the loop
                await self.detach(ws)
        return delivered

    def events_since(self, seq: int) -> list[dict[str, Any]]:
        return [e for e in self.events if e["seq"] > seq]

    async def handle_client_message(self, msg: dict[str, Any]) -> None:
        """Telemetry and safety requests coming from Godot."""
        kind = msg.get("type")
        if kind == "state":
            self.agent_states[msg.get("agent", "?")] = msg
        elif kind == "snapshot":
            data = msg.get("data", {})
            self.meeting_active = bool(data.get("meeting_active", False))
            for agent in data.get("agents", []):
                self.agent_states[agent.get("agent", "?")] = agent
        elif kind == "review_request":
            agent = msg.get("agent", "?")
            msg["received_at"] = time.time()
            self.pending_reviews[agent] = msg
            log.info("REVIEW REQUEST from %s: %s", agent, msg.get("task"))
            await voice.announce(msg.get("prompt") or f"{agent} has finished {msg.get('task')}. Do you approve?")
        elif kind in ("task_started", "task_completed"):
            log.info("%s %s: %s", msg.get("agent"), kind.replace("_", " "), msg.get("task"))
            if kind == "task_completed":
                self.pending_reviews.pop(msg.get("agent", ""), None)
        elif kind == "hello":
            log.info("Godot says hello (%s).", msg.get("engine", "?"))
        elif kind == "ack" and not msg.get("ok", True):
            log.warning("Godot rejected %s: %s", msg.get("ref"), msg)


# =============================================================================
#  Mac audio interface (voice confirmation prompt)
# =============================================================================
class VoiceAnnouncer:
    """Speaks review prompts through the Mac's audio output using `say`.

    Swap `announce` for your own TTS / speech-to-text loop. Whatever captures
    the human's "yes"/"no" should call POST /review.
    """

    def __init__(self) -> None:
        self.enabled = VOICE_ENABLED and platform.system() == "Darwin" and shutil.which("say") is not None
        self._speaking: asyncio.Lock | None = None

    async def announce(self, text: str) -> None:
        if not self.enabled:
            log.info("[voice disabled] %s", text)
            return
        if self._speaking is None:
            self._speaking = asyncio.Lock()
        # Fire-and-forget so the WebSocket loop is never blocked by speech.
        asyncio.create_task(self._say(text))

    async def _say(self, text: str) -> None:
        assert self._speaking is not None
        async with self._speaking:  # serialize so prompts don't talk over each other
            args = ["say"] + (["-v", VOICE_NAME] if VOICE_NAME else []) + [text]
            proc = await asyncio.create_subprocess_exec(*args)
            await proc.wait()


voice = VoiceAnnouncer()


# =============================================================================
#  Background job engine
# =============================================================================
@dataclass
class Job:
    id: str
    request: CommandRequest
    created_at: float = field(default_factory=time.time)
    status: Literal["queued", "running", "done", "failed"] = "queued"
    result: dict[str, Any] | None = None
    error: str | None = None
    done: asyncio.Event = field(default_factory=asyncio.Event)

    def to_dict(self) -> dict[str, Any]:
        return {"job_id": self.id, "status": self.status, "text": self.request.text,
                "result": self.result, "error": self.error, "created_at": self.created_at}


class CommandEngine:
    """Queue + worker(s): commands are routed off the request thread so a
    slow LLM never blocks the API or the WebSocket loop."""

    def __init__(self, router: OllamaRouter, hub: GodotHub) -> None:
        self.router = router
        self.hub = hub
        self.queue: asyncio.Queue[Job] = asyncio.Queue()
        self.jobs: dict[str, Job] = {}
        self._workers: list[asyncio.Task[None]] = []

    def start(self) -> None:
        self._workers = [asyncio.create_task(self._worker(i)) for i in range(WORKER_COUNT)]

    async def stop(self) -> None:
        for w in self._workers:
            w.cancel()
        await asyncio.gather(*self._workers, return_exceptions=True)

    def submit(self, request: CommandRequest) -> Job:
        job = Job(id=f"job-{uuid.uuid4().hex[:8]}", request=request)
        self.jobs[job.id] = job
        # Keep memory bounded: forget the oldest finished jobs.
        if len(self.jobs) > 500:
            for old_id in [j.id for j in self.jobs.values() if j.done.is_set()][:100]:
                self.jobs.pop(old_id, None)
        self.queue.put_nowait(job)
        return job

    async def _worker(self, index: int) -> None:
        while True:
            job = await self.queue.get()
            job.status = "running"
            try:
                intent, source = await self.router.route(job.request.text, job.request.agent_hint)
                payload = intent_to_payload(intent, task_id=f"t-{uuid.uuid4().hex[:6]}")
                delivered = await self.hub.broadcast(payload)
                job.result = {"payload": payload, "source": source, "reasoning": intent.reasoning,
                              "delivered_to": delivered}
                job.status = "done"
                if delivered == 0:
                    log.warning("No Godot client connected — payload queued in /events only.")
            except Exception as exc:  # noqa: BLE001 — a job failure must not kill the worker
                log.exception("Worker %d failed job %s", index, job.id)
                job.status, job.error = "failed", str(exc)
            finally:
                job.done.set()
                self.queue.task_done()


# =============================================================================
#  FastAPI application
# =============================================================================
hub = GodotHub()


@asynccontextmanager
async def lifespan(app: FastAPI):
    client = httpx.AsyncClient()
    router = OllamaRouter(client)
    engine = CommandEngine(router, hub)
    engine.start()
    app.state.router = router
    app.state.engine = engine
    if await router.is_available():
        log.info("Ollama reachable at %s (model %s).", OLLAMA_URL, OLLAMA_MODEL)
    else:
        log.warning("Ollama NOT reachable at %s — keyword fallback router will be used.", OLLAMA_URL)
    log.info("A.V.A bridge listening on http://%s:%d  (Godot WS: /ws/godot)", HOST, PORT)
    try:
        yield
    finally:
        await engine.stop()
        await client.aclose()


app = FastAPI(
    title="A.V.A Mars Sandbox Bridge",
    version="1.0.0",
    description="Routes user commands through Ollama/Qwen and drives the Godot agent colony.",
    lifespan=lifespan,
)


@app.get("/health")
async def health() -> dict[str, Any]:
    return {
        "ok": True,
        "godot_clients": hub.client_count,
        "ollama": await app.state.router.is_available(),
        "model": OLLAMA_MODEL,
        "queued_jobs": app.state.engine.queue.qsize(),
        "pending_reviews": len(hub.pending_reviews),
        "voice": voice.enabled,
    }


@app.post("/command", status_code=200)
async def post_command(req: CommandRequest) -> dict[str, Any]:
    """Free-text command → Ollama/Qwen → validated Godot payload → pushed to Godot."""
    job: Job = app.state.engine.submit(req)
    if not req.wait:
        return {"job_id": job.id, "status": job.status}
    try:
        await asyncio.wait_for(job.done.wait(), timeout=OLLAMA_TIMEOUT + 10)
    except asyncio.TimeoutError:
        # Still processing in the background; the client can poll /jobs/{id}.
        return {"job_id": job.id, "status": job.status}
    if job.status == "failed":
        raise HTTPException(status_code=500, detail=job.to_dict())
    return job.to_dict()


@app.get("/jobs/{job_id}")
async def get_job(job_id: str) -> dict[str, Any]:
    job = app.state.engine.jobs.get(job_id)
    if job is None:
        raise HTTPException(404, f"unknown job '{job_id}'")
    return job.to_dict()


@app.post("/task")
async def post_task(req: DirectTaskRequest) -> dict[str, Any]:
    """Direct, deterministic dispatch (no LLM)."""
    role = AgentRole(req.agent)
    payload = {
        "type": "task",
        "task_id": f"t-{uuid.uuid4().hex[:6]}",
        "agent": role.value,
        "task": req.task.strip(),
        "building": (req.building or ROLE_HOME_HUB[role]).value,
        "duration": req.duration or 10.0,
        "priority": "normal",
    }
    return {"payload": payload, "delivered_to": await hub.broadcast(payload)}


@app.post("/meeting")
async def post_meeting(req: MeetingRequest) -> dict[str, Any]:
    """Global MEETING trigger: all agents route to the Command Center."""
    payload: dict[str, Any] = {"type": "meeting", "action": req.action}
    if req.duration:
        payload["duration"] = req.duration
    return {"payload": payload, "delivered_to": await hub.broadcast(payload)}


@app.post("/review")
async def post_review(decision: ReviewDecision) -> dict[str, Any]:
    """Human confirmation for an agent waiting at the Review Terminal."""
    role = normalize_role(decision.agent)
    if role is None:
        raise HTTPException(422, f"unknown agent '{decision.agent}'")
    pending = hub.pending_reviews.get(role.value)
    if pending is None:
        raise HTTPException(409, f"{role.value} has no pending review")
    if decision.task_id and decision.task_id != pending.get("task_id"):
        raise HTTPException(409, f"task_id mismatch (pending: {pending.get('task_id')})")
    hub.pending_reviews.pop(role.value, None)
    payload = {
        "type": "review_result",
        "agent": role.value,
        "task_id": pending.get("task_id", ""),
        "approved": decision.approved,
        "feedback": decision.feedback,
    }
    await voice.announce(f"{'Approved' if decision.approved else 'Sent back'}: {pending.get('task', 'task')}.")
    return {"payload": payload, "delivered_to": await hub.broadcast(payload)}


@app.get("/reviews")
async def get_reviews() -> list[dict[str, Any]]:
    return list(hub.pending_reviews.values())


@app.get("/agents")
async def get_agents() -> dict[str, Any]:
    """Last known agent states (asks Godot for a fresh snapshot, too)."""
    await hub.broadcast({"type": "snapshot_request"})
    return {"meeting_active": hub.meeting_active, "agents": hub.agent_states}


@app.get("/events")
async def get_events(since: int = Query(0, ge=0)) -> dict[str, Any]:
    """Polling fallback: every payload broadcast after sequence `since`."""
    events = hub.events_since(since)
    return {"events": events, "last_seq": events[-1]["seq"] if events else since}


@app.websocket("/ws/godot")
async def ws_godot(ws: WebSocket) -> None:
    """Persistent link to agent_bridge.gd."""
    await hub.attach(ws)
    try:
        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                log.warning("Non-JSON from Godot: %r", raw[:200])
                continue
            if isinstance(msg, dict):
                await hub.handle_client_message(msg)
    except WebSocketDisconnect:
        pass
    finally:
        await hub.detach(ws)


# =============================================================================
#  Entrypoint
# =============================================================================
if __name__ == "__main__":
    # Bound to localhost on purpose: this API drives agents, so don't expose it on the LAN.
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
