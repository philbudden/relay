You are acting as a senior platform engineer and GitOps architect.

Create a high-quality `AGENTS.md` file for a new repository that manages a standalone Podman host using:

- Ansible
- systemd
- Quadlet

This repository is responsible for **container lifecycle management only**.

---

## Architectural Intent

The project must:

- Follow a GitOps mindset (Git is the source of truth)
- Be fully declarative
- Be idempotent
- Be reproducible from scratch
- Avoid imperative drift
- Be minimal and boring
- Avoid hidden automation or magic

This project is **not** responsible for full OS provisioning.

Provisioning of the base operating system happens elsewhere.

---

## Scope Boundaries

The repository:

- Manages Podman containers via Quadlet definitions
- Manages required systemd units
- Manages image versions (pinned where appropriate)
- Enables automatic updates in a controlled, explicit way
- Pulls configuration from GitHub
- Ensures containers are restarted deterministically when definitions change

The repository must **not**:

- Perform general OS configuration
- Act as a workstation bootstrap
- Introduce Kubernetes
- Use docker-compose
- Use long-running imperative shell scripts
- Blur boundaries between host provisioning and container management

OS changes must be:
- Minimal
- Explicit
- Strictly required for container lifecycle management
- Clearly documented in AGENTS.md

---

## Environment Assumptions

Short-term:
- Debian host
- systemd-based
- Podman installed

Long-term:
- Migration target: Blueberry (custom Fedora IoT-based image)
- Must not assume Debian-specific behaviour unless abstracted
- Avoid Debian-only hacks
- Prefer portable patterns compatible with Fedora IoT

The AGENTS.md file must explicitly call out portability considerations.

---

## Required Sections in AGENTS.md

1. Project Philosophy
2. Scope and Non-Goals
3. Target Architecture
4. GitOps Workflow Model
5. Directory Structure Conventions
6. Quadlet Conventions (naming, version pinning, restart policy, logging)
7. Ansible Role Design Principles
8. systemd Integration Model
9. Update Strategy (image updates, configuration changes)
10. Testing Strategy (linting, idempotency validation, dry runs)
11. Migration Considerations (Debian → Blueberry)
12. Anti-Patterns to Avoid

---

## Tone & Style Requirements

The AGENTS.md must:

- Be explicit and opinionated
- Prevent scope creep
- Provide guardrails for future coding agents
- Define conventions clearly
- Avoid ambiguity
- Avoid verbosity without substance

This document should act as a strict architectural contract for the repository.
