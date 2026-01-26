---
description: Update project documentation (STATUS_REPORT.md) with latest progress and push to git
---

Use this workflow to automatically capture the current development state, update the documentation, and sync with the remote repository.

1. **Summarize Progress**: Analyze recent changes in the codebase and the current session's conversation to identify what has been completed and what is pending. Use `git diff` or `git log -n 5` to help.

2. **Update STATUS_REPORT.md**: 
    - Update the "**最後更新:**" date to today's date (%Y-%m-%d).
    - Review the "Pending Tasks" section. Move any recently completed tasks to the "Completed Tasks" section with a date.
    - Add any new tasks identified during the session to "Pending Tasks".
    - If there are significant architectural changes, update the "Project Overview" or "Component Status" tables.

3. **Check for HANDOVER.md**: If the user prefers daily handover notes, also update `HANDOVER.md` with a summary of today's accomplishments.

// turbo
4. **Git Commit and Push**:
    - Run `git add .`
    - Run `git commit -m "docs: progress update to STATUS_REPORT.md and sync changes"`
    - Run `git push`

5. **Confirmation**: Report to the user that the documentation has been updated and pushed successfully.
