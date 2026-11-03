# Feature Request: Projects
Users have a growing list of tasks and no way to organise them. We want
users to group their tasks into projects.
## What we need
1. **Create a project** with a name. Project names must be unique per
user.
2. **Assign a task to a project.** A task belongs to at most one project.
A user can move a task to another of their own projects, or take it out of
a project.
3. **List a project's tasks**, including how many of them are completed.
4. **Archive a project.** An archived project no longer shows up in the
project list, but its tasks are kept.
## Additional context
- Follow the existing feature slices (`Application/TSK001Tasks`,
`Application/CMT003Comments`). The new slice is `PRJ004Projects`.
- Users may only see and change their own projects.
- Publish domain events, like the existing features do.
- The frontend should let users filter the task list by project.