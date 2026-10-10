#!/usr/bin/env bash
# Rebuilds the drop-in models and the full place from src/ (needs Rojo 7 on PATH).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p models
rojo build projects/GameConfig.project.json -o models/1_ReplicatedStorage_GameConfig.rbxmx
rojo build projects/Shared.project.json -o models/2_ReplicatedStorage_Shared.rbxmx
rojo build projects/Server.project.json -o models/3_ServerScriptService_AvoidTheSnipers_Server.rbxmx
rojo build projects/Client.project.json -o models/4_StarterPlayerScripts_AvoidTheSnipers_Client.rbxmx
rojo build projects/RbxCharacterSounds.project.json -o models/5_StarterPlayerScripts_RbxCharacterSounds.rbxmx
rojo build ../default.project.json -o AvoidTheSnipers.rbxlx
