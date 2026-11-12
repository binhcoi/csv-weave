If you are working in a worktree, you need to maintain a separate a docker container to host the app. You can take over existing container if it's for your worktree. Don't worry about worktree switching mid conversation, each prompt might be in a different worktree. Focus on your worktree only, don't worry about main or other work tree code status.

- Run your container with the `.env` file 
- Choose ports. Be careful not to conflict with concurrent worktree's container. `API_PORT` serves the Rails API; `UI_PORT` is reserved for the frontend dev server.
- Mount worktree source at /app. The repository root is mounted, so `/app/backend` is the Rails app and `/app/bin` holds the wrappers.
- Join dev_default network to access common db.
- Run `bin/setup` in that container before first start up to install dependencies and create its db. Worktree db might be out of sync, make sure it's in sync before testing.
- After adding a new job class, restart the container. The worker only loads new job files at boot
- Run commands through the root wrappers (`bin/rails`, `bin/test`, `bin/e2e`, `bin/lint`); they work from any directory, so `docker exec <container> bin/test` is enough.
- If the Rails app moves or is restructured while a server is running, restart the container. The old process keeps its original working directory and starts failing health checks.