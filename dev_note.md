If you are working in a worktree, you need to maintain a separate a docker container to host the app. You can take over existing container if it's for your worktree. Don't worry about worktree switching mid conversation, each prompt might be in a different work tree.

- Run your container with the `.env` file 
- Choose a port. Be careful not to conflict with concurrent worktree's container. 
- Mount worktree source at /app
- Join dev_default network to access common db.
- Run `bin/rails db:prepare` in that container before first start up to create its db.
- Add `SOLID_QUEUE_IN_PUMA=1` to `.env` so the Solid Queue worker runs inside Puma. `db:prepare` also creates the `<DB_NAME>_development_queue` database.
- After adding a new job class, restart the container. The worker only loads new job files at boot; edits to existing jobs reload automatically.
