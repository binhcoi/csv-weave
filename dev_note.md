If you are working in a worktree, you need to maintain a separate a docker container to host the app. You can take over existing container if it's for your worktree. It's possible that each prompt will switch your worktree. Focus on your current worktree only, don't worry about main or other work tree code status. Do not stage or commit without permission.

- Run your container with the `.env` file 
- Choose ports. Be careful not to conflict with concurrent worktree's container. `API_PORT` serves the Rails API; `UI_PORT` serves the Vite frontend dev server (container port 5173).
- The repository root is mounted at `/app`, so `/app/backend` is the Rails app, `/app/frontend` the web interface, and `/app/bin` holds the wrappers.
- Join dev_default network to access common db.
- Build the image from your worktree (`docker build -f Dockerfile.dev --target e2e -t csv-weave-<worktree>:<tag> .`) and start the container with `bash -c 'bin/setup && exec bin/dev'`.
- When `Dockerfile.dev` changes, rebuild your worktree's image and replace your worktree's container (stop, remove, run with the same name, ports, network, and mount). Don't test against another worktree's container or a stale image, and don't leave extra containers behind.
- Run `bin/setup` in that container before first start up to install dependencies (including `frontend/node_modules`, which the bind mount hides from the image) and create its db. Worktree db might be out of sync, make sure it's in sync before testing.
- After adding a new job class, restart the container. The worker only loads new job files at boot. This also restarts Vite, losing hot-reload state.
- `bin/dev` runs `Procfile.dev` through foreman. If either process exits, foreman stops the other and the container exits.
- Run commands through the root wrappers (`bin/rails`, `bin/test`, `bin/e2e`, `bin/lint`, `bin/ui`); they work from any directory, so `docker exec <container> bin/test` is enough. With `docker exec -w <subdir>`, use `/app/bin/...`.
- If the Rails app moves or is restructured while a server is running, restart the container. The old process keeps its original working directory and starts failing health checks.