# Git workflow requested by the user

- This repository tracks the workspace. The Flutter app and Flask backend are in `financial_advisor/`.
- Normal questions, explanations, and read-only checks that do not change application code must not trigger commit-message or push questions, or empty commits. Recording a chat preference in this file alone is not an application code change; leave that update pending without a commit prompt unless the user explicitly asks to commit it.
- After each completed code-change request, run the appropriate checks and prepare the related changes for a local commit. Wait for the user's chosen commit message before creating the commit.
- When a commit is needed for application code changes or the user explicitly requests a commit, ask what commit message they want. This also applies to any required merge commit. Use the message they provide for that commit; do not derive a message from their task request or invent one. If they already explicitly supplied a commit message for the pending commit, use it without asking again. Never include credentials or other secrets in commit messages.
- Inspect the staged changes before committing. Keep credentials, `.env` files, receipt uploads, generated builds, virtual environments, caches, and local backups out of Git. Preserve unrelated user changes and avoid mixing them into a task commit.
- After the local commit is complete, report its short hash and ask whether the user wants that commit pushed to GitHub. Push only after the user explicitly approves that push; approval for one push is not approval for later pushes.
- Do not amend, reset, or rewrite existing history unless the user explicitly requests it.
- Do not create application documentation unless the user requests it.
- Ask before every live SerpAPI key use. Never place a key in source code, logs, commit messages, or tool output.
- The user manages Flask manually. Do not start, stop, or restart Flask unless asked.
