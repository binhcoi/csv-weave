If you are working in a worktree, you need to maintain a separate a docker container to host the app. You can take over existing container if it's for your worktree. Don't worry about worktree switching mid conversation, each prompt might be in a different work tree.

- Run your container with the `.env` file 
- Choose a port. Be careful not to conflict with concurrent worktree's container. 
- Mount worktree source at /app
- Join dev_default network to access common db.
- Run `bin/rails db:prepare` in that container before first start up to create its db.
 