# PBI: Group tasks into projects

Source: GitHub issue #1 "Group tasks into projects" (msellies/modern-copilot-.NET-Todo-app), and `spec.md`.

## Description

Users have a growing list of tasks and no way to organise them. Users can create named projects, assign their tasks to at most one of them, see how many tasks in a project are completed, and archive projects they no longer need. Archiving hides a project from the project list but keeps its tasks. The task list can be filtered by project in the frontend.

The new feature slice is `Application/PRJ004Projects`, following the existing slices (`TSK001Tasks`, `CMT003Comments`).

## Data model

**Project** (new entity, `Domain/Entities/Project.cs`)

| Field | Type | Notes |
|---|---|---|
| Id | int | PK |
| Name | string | Required, non-blank |
| UserId | int | Owner, FK to `User` |
| IsArchived | bool | Default `false` |
| CreatedAt | DateTime | UTC, set on create |

- Unique index on `(UserId, Name)` where `IsArchived = false` (filtered index). Archived names are not reserved.

**TaskItem** (existing) gains:

| Field | Type | Notes |
|---|---|---|
| ProjectId | int? | Null = not in a project. FK to `Project`. |

- A task belongs to at most one project, enforced by the single nullable column.
- EF Core migration required (`AddProjects`). The existing `InitialCreate` migration is the only one so far.

## Endpoints

Base route `api/v1/projects` (new `ProjectsController`, `[Authorize]`, `[ApiVersion("1.0")]`, `[EnableRateLimiting("fixed")]`, `[Produces("application/json")]`, same as the other controllers). Success responses use `Ok(...)` like the existing controllers.

The caller identifies the owner with a `userId` parameter. How `userId` is supplied and authenticated is out of scope for this project. Every endpoint checks that the project (or task) belongs to the given `userId`.

| # | Method | Route | Request | Response |
|---|---|---|---|---|
| E1 | POST | `/api/v1/projects` | body `{ "name": string, "userId": int }` | 200 `Project` |
| E2 | GET | `/api/v1/projects?userId={int}` | query | 200 `Project[]` (non-archived, owned by `userId`) |
| E3 | GET | `/api/v1/projects/{id}/tasks?userId={int}` | path + query | 200 `{ "projectId", "name", "totalTasks", "completedTasks", "tasks": TaskItem[] }` |
| E4 | PUT | `/api/v1/projects/{id}/archive?userId={int}` | path + query | 200 `Project` (with `isArchived: true`) |
| E5 | PUT | `/api/v1/projects/{id}/tasks/{taskId}?userId={int}` | path + query, no body | 200 `TaskItem` (assigns, or moves, the task to project `{id}`) |
| E6 | DELETE | `/api/v1/projects/{id}/tasks/{taskId}?userId={int}` | path + query | 200 `TaskItem` (removes the task from project `{id}`, `ProjectId` set to null) |
| E7 | GET | `/api/v1/tasks?userId={int}&projectId={int}` | query, added to the existing `TasksController.GetAll` | 200 `TaskItem[]` filtered by project |

Notes:
- E5 and E6 live in `ProjectsController` because the project is the resource in the path. E7 is an extension of the existing `TasksController.GetAll`.
- Taking a task out of a project uses DELETE on the same path, because the project is part of the path and there is no project to send in a body.
- E3 returns the completed count so the client does not compute it. `totalTasks` counts all tasks in the project.

### Status codes per scenario

| Endpoint | Scenario | Status | Source |
|---|---|---|---|
| E1 | Created | 200 | |
| E1 | Name blank or whitespace | 400 | `ArgumentException` |
| E1 | User does not exist | 400 | `ArgumentException` (same as `CreateTaskHandler`) |
| E1 | Duplicate name for this user (non-archived project) | 409 | `InvalidOperationException` |
| E2 | Success, including empty list | 200 | |
| E2 | Archived projects | not returned | |
| E3 | Success | 200 | |
| E3 | Project not found | 404 | `KeyNotFoundException` |
| E3 | Project belongs to another `userId` | 404 | Existence is not revealed |
| E3 | Project is archived | 200 | Tasks are kept, so the project stays readable |
| E4 | Archived | 200 | |
| E4 | Already archived | 200 | Idempotent |
| E4 | Not found or not owned | 404 | |
| E5 | Assigned or moved | 200 | |
| E5 | Project not found or not owned by `userId` | 404 | |
| E5 | Task not found or task not owned by `userId` | 404 | |
| E5 | Project is archived | 409 | `InvalidOperationException`. Archived projects do not accept tasks. |
| E6 | Removed | 200 | |
| E6 | Task not in this project | 404 | Nothing changes |
| E6 | Project or task not found or not owned | 404 | |
| E7 | Success | 200 | |
| E7 | Project not found or not owned | 404 | |

Status mapping follows `ExceptionHandlingMiddleware`: `ArgumentException` → 400, `KeyNotFoundException` → 404, `InvalidOperationException` → 409.

## Business rules

1. **Create:** name is trimmed; blank names are rejected. Names are unique per user among non-archived projects.
2. **Assign (E5):** a task has at most one project. Assigning a task to another project replaces the old value.
3. **Remove (E6):** sets `ProjectId` to null. Only succeeds when the task is currently in the given project.
4. **Owner match:** the target project must belong to the same user as the task. Cross-user assignment is rejected.
5. **Archive:** sets `IsArchived = true`. Archived projects are excluded from E2. Their tasks keep their `ProjectId` and are not deleted or changed.
6. **Archive is one-way** in this PBI. There is no unarchive endpoint.
7. **Archived projects:** tasks can still be read (E3) and moved out (E6). Tasks cannot be assigned into them (E5).
8. **Completed count:** counts tasks in the project with `IsCompleted = true`. Archived projects still report counts (E3).
9. **Task completion** (existing `PUT /tasks/{id}/complete`) does not change the project.
10. **Deleting** projects and deleting users are out of scope. Because `ProjectId` is nullable, a future project delete can set it to null without losing tasks.

## Authorization

- All endpoints require `[Authorize]`.
- Every endpoint takes `userId` and checks ownership against it. Users may only read and change their own projects and their own tasks' project assignment.
- Ownership failures return 404 rather than 403, so the existence of other users' projects is not revealed.
- How the caller's identity becomes `userId` is out of scope for this project.

## Domain events

Publish through `IPublisher`, like the existing features. Each event is a `record` in `Domain/Events` implementing `INotification`.

| Event | Published by | Payload |
|---|---|---|
| `ProjectCreatedEvent(ProjectId, Name, UserId)` | E1 | |
| `ProjectArchivedEvent(ProjectId, UserId)` | E4 | |
| `TaskMovedToProjectEvent(TaskId, FromProjectId?, ToProjectId?, UserId)` | E5, E6 | `FromProjectId` is null when the task had no project; `ToProjectId` is null on removal |

Handlers: add a `ProjectEventHandler` in `Application/EventHandlers` that logs each event, the same as `TaskEventHandler` and `CommentEventHandler`.

## Caching

Existing cache keys: `tasks:all`, `tasks:user:{id}`, `comments:task:{id}`. Cached queries use a 30-second duration.

- New keys in `CacheKeys`: `projects:user:{userId}` (E2), `projects:{id}:tasks` (E3), and `tasks:project:{projectId}` (E7).
- E1 and E4 invalidate `projects:user:{userId}`.
- E4 also invalidates `projects:{id}:tasks`.
- E5 and E6 invalidate `tasks:all`, `tasks:user:{ownerId}`, `projects:{id}:tasks`, `tasks:project:{id}`, and, for the previous project, `projects:{oldId}:tasks` and `tasks:project:{oldId}`.
- E7 uses `tasks:project:{projectId}`. It does not reuse `tasks:user:{id}`, because that key holds unfiltered results.

## Acceptance criteria

1. A user can create a project with a name; the response has `isArchived: false`.
2. Creating a second non-archived project with the same name for the same user returns 409. The same name for a different user succeeds. A name whose earlier project is archived can be reused.
3. A blank or whitespace name returns 400.
4. `GET /api/v1/projects?userId=` returns only that user's non-archived projects.
5. E5 assigns a task to a project; the task then shows that `projectId`.
6. E5 on a task already in another project replaces the first; the task is in one project only.
7. E6 removes a task from its project and sets `projectId` to null.
8. E5 with a project owned by another user returns 404 and changes nothing.
9. E5 into an archived project returns 409 and changes nothing.
10. E3 returns `totalTasks` and `completedTasks` correct for the project, and includes the task list.
11. After a project is archived, it no longer appears in E2, and its tasks still exist and keep their `projectId`.
12. Archiving an already archived project returns 200 and changes nothing.
13. E6 on a task not in that project returns 404 and changes nothing.
14. E7 returns only the tasks in that project for the given `userId`.
15. Requests for another user's project return 404 on E3, E4, E5, E6 and E7.
16. Each event above is published on success and not on failure.
17. Cache entries are invalidated so that a task move is visible on the next read within the 30-second cache window.
18. The EF Core migration adds the `Projects` table, the `TaskItems.ProjectId` column, and the filtered unique index on `(UserId, Name)` where `IsArchived = false`.
19. Frontend: the task list has a project filter that uses E7.

## Decisions

Resolved with the product owner:

- Identity: `userId` is passed as a parameter. How it is supplied is out of scope for this project.
- Archived names are not reserved; uniqueness applies only to non-archived projects.
- Duplicate name returns 409.
- E7 combines `userId` and `projectId` with AND.
- Tasks can be moved out of an archived project, but not into one.
- Task assignment uses `/projects/{id}/tasks/{taskId}` (E5 and E6), not `/tasks/{taskId}/project`.

## Open questions

None open. Two items are noted for later and are not part of this PBI:

- Listing tasks with no project (`projectId=none`) is not included.
- `CompleteTaskCommand` invalidates only `tasks:all`, not `tasks:user:{id}`. This is an existing gap, out of scope here.
