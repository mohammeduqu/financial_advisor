# Git workflow requested by the user

- This repository tracks the workspace. The Flutter app and Flask backend are in `financial_advisor/`.
- After each completed code-change request, run the appropriate checks and commit the related changes locally. Do not leave completed code work uncommitted unless the user explicitly says otherwise or a real blocker prevents committing.
- Use the user's chat request as the commit message. For a long request, use its first sentence as the subject and include the full request in the body. Redact credentials or other secrets from commit messages.
- Inspect the staged changes before committing. Keep credentials, `.env` files, receipt uploads, generated builds, virtual environments, caches, and local backups out of Git. Preserve unrelated user changes and avoid mixing them into a task commit.
- After the local commit is complete, report its short hash and ask whether the user wants that commit pushed to GitHub. Push only after the user explicitly approves that push; approval for one push is not approval for later pushes.
- Do not amend, reset, or rewrite existing history unless the user explicitly requests it.
- Do not create application documentation unless the user requests it.
- Ask before every live SerpAPI key use. Never place a key in source code, logs, commit messages, or tool output.
- The user manages Flask manually. Do not start, stop, or restart Flask unless asked.
