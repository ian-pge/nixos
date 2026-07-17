# RunPod Manager for Vicinae

A local Vicinae extension for managing existing RunPod Pods through the official REST API.

## Features

- Lists running, stopped, and terminated Pods.
- Shows GPU, hourly cost, image, memory, volume, public IP, and lifecycle details.
- Starts/resumes stopped Pods after confirmation.
- Stops running Pods after confirmation.
- Copies Pod IDs and SSH commands when available.
- Opens the RunPod Console.

## Authentication

Create a restricted API key in the RunPod Console with permission to read, start, and stop Pods. Enter it in **Vicinae Settings → Extensions → RunPod Manager**. The key remains a Vicinae password preference and is never written into this repository or the Nix store.

## API

Uses the GA REST API at `https://rest.runpod.io/v1`:

- `GET /pods`
- `POST /pods/{podId}/start`
- `POST /pods/{podId}/stop`

Start and stop requests are bodyless. The API only exposes `RUNNING`, `EXITED`, and `TERMINATED` expected statuses; it does not expose a distinct authoritative `STARTING` status.
