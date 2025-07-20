;; Transfer Contract
;; A secure, role-based token transfer management system
;; Built on Stacks blockchain for transparent and controlled asset movement

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROJECT-NOT-FOUND (err u101))
(define-constant ERR-MILESTONE-NOT-FOUND (err u102))
(define-constant ERR-TASK-NOT-FOUND (err u103))
(define-constant ERR-INVALID-DEADLINE (err u104))
(define-constant ERR-USER-NOT-FOUND (err u105))
(define-constant ERR-ALREADY-EXISTS (err u106))
(define-constant ERR-INVALID-STATUS (err u107))
(define-constant ERR-INVALID-ROLE (err u108))
(define-constant ERR-DEPENDENCY-INCOMPLETE (err u109))

;; Status constants
(define-constant STATUS-PENDING u1)
(define-constant STATUS-IN-PROGRESS u2)
(define-constant STATUS-COMPLETED u3)
(define-constant STATUS-DELAYED u4)
(define-constant STATUS-CANCELLED u5)

;; Role constants
(define-constant ROLE-ADMIN u1)
(define-constant ROLE-MEMBER u2)
(define-constant ROLE-VIEWER u3)

;; Data structures

;; Stores project information
(define-map projects
  { project-id: uint }
  {
    name: (string-ascii 100),
    description: (string-utf8 500),
    creator: principal,
    created-at: uint,
    status: uint,
    deadline: uint
  }
)

;; Tracks all project IDs
(define-data-var next-project-id uint u1)

;; Stores milestone information
(define-map milestones
  { project-id: uint, milestone-id: uint }
  {
    name: (string-ascii 100),
    description: (string-utf8 500),
    deadline: uint,
    status: uint
  }
)

;; Tracks milestone IDs per project
(define-map project-milestone-count
  { project-id: uint }
  { count: uint }
)

;; Stores task information
(define-map tasks
  { project-id: uint, milestone-id: uint, task-id: uint }
  {
    name: (string-ascii 100),
    description: (string-utf8 500),
    assignee: (optional principal),
    deadline: uint,
    status: uint,
    dependencies: (list 10 uint)
  }
)

;; Tracks task IDs per milestone
(define-map milestone-task-count
  { project-id: uint, milestone-id: uint }
  { count: uint }
)

;; Stores team member associations and roles
(define-map team-members
  { project-id: uint, member: principal }
  { role: uint }
)

;; Stores update and communication history
(define-map communications
  { project-id: uint, comm-id: uint }
  {
    sender: principal,
    timestamp: uint,
    message: (string-utf8 1000),
    context-type: (string-ascii 20), ;; "project", "milestone", or "task"
    context-id: uint                 ;; project-id, milestone-id, or task-id
  }
)

;; Tracks communication IDs per project
(define-map project-comm-count
  { project-id: uint }
  { count: uint }
)

;; Private functions

;; Helper to check if user is authorized for a specific role
(define-private (is-authorized (project-id uint) (required-role uint))
  (let (
    (user-role (get role (default-to { role: u0 } (map-get? team-members { project-id: project-id, member: tx-sender }))))
    (is-creator (is-eq tx-sender (get creator (unwrap! (map-get? projects { project-id: project-id }) false))))
  )
    (or is-creator (<= required-role user-role))
  )
)


;; Helper to check if deadline is valid (in the future)
(define-private (is-valid-deadline (deadline uint))
  (> deadline block-height)
)

;; Read-only functions

;; Get project details
(define-read-only (get-project (project-id uint))
  (map-get? projects { project-id: project-id })
)

;; Get milestone details
(define-read-only (get-milestone (project-id uint) (milestone-id uint))
  (map-get? milestones { project-id: project-id, milestone-id: milestone-id })
)

;; Get task details
(define-read-only (get-task (project-id uint) (milestone-id uint) (task-id uint))
  (map-get? tasks { project-id: project-id, milestone-id: milestone-id, task-id: task-id })
)

;; Get team member role
(define-read-only (get-member-role (project-id uint) (member principal))
  (map-get? team-members { project-id: project-id, member: member })
)


;; Public functions

;; Create a new project
(define-public (create-project (name (string-ascii 100)) (description (string-utf8 500)) (deadline uint))
  (let (
    (project-id (var-get next-project-id))
  )
    ;; Verify deadline is in the future
    (asserts! (is-valid-deadline deadline) ERR-INVALID-DEADLINE)
    
    ;; Store project data
    (map-set projects 
      { project-id: project-id }
      {
        name: name,
        description: description,
        creator: tx-sender,
        created-at: block-height,
        status: STATUS-PENDING,
        deadline: deadline
      }
    )
    
    ;; Initialize project milestone count
    (map-set project-milestone-count
      { project-id: project-id }
      { count: u0 }
    )
    
    ;; Initialize project communication count
    (map-set project-comm-count
      { project-id: project-id }
      { count: u0 }
    )
    
    ;; Add creator as admin
    (map-set team-members
      { project-id: project-id, member: tx-sender }
      { role: ROLE-ADMIN }
    )
    
    ;; Increment project counter
    (var-set next-project-id (+ project-id u1))
    
    (ok project-id)
  )
)

;; Add a team member to a project
(define-public (add-team-member (project-id uint) (member principal) (role uint))
  (begin
    ;; Ensure project exists
    (asserts! (is-some (map-get? projects { project-id: project-id })) ERR-PROJECT-NOT-FOUND)
    
    ;; Check authorization - only admins can add members
    (asserts! (is-authorized project-id ROLE-ADMIN) ERR-NOT-AUTHORIZED)
    
    ;; Validate role
    (asserts! (or (is-eq role ROLE-ADMIN) (is-eq role ROLE-MEMBER) (is-eq role ROLE-VIEWER)) ERR-INVALID-ROLE)
    
    ;; Check if the member is already on the team
    (asserts! (is-none (map-get? team-members { project-id: project-id, member: member })) ERR-ALREADY-EXISTS)
    
    ;; Add member with specified role
    (map-set team-members
      { project-id: project-id, member: member }
      { role: role }
    )
    
    (ok true)
  )
)

;; Create a new milestone for a project
(define-public (create-milestone (project-id uint) (name (string-ascii 100)) (description (string-utf8 500)) (deadline uint))
  (let (
    (milestone-count-data (default-to { count: u0 } (map-get? project-milestone-count { project-id: project-id })))
    (milestone-count (get count milestone-count-data))
    (new-milestone-id (+ milestone-count u1))
  )
    ;; Ensure project exists
    (asserts! (is-some (map-get? projects { project-id: project-id })) ERR-PROJECT-NOT-FOUND)
    
    ;; Check authorization - only admins can create milestones
    (asserts! (is-authorized project-id ROLE-ADMIN) ERR-NOT-AUTHORIZED)
    
    ;; Verify deadline is in the future
    (asserts! (is-valid-deadline deadline) ERR-INVALID-DEADLINE)
    
    ;; Store milestone data
    (map-set milestones
      { project-id: project-id, milestone-id: new-milestone-id }
      {
        name: name,
        description: description,
        deadline: deadline,
        status: STATUS-PENDING
      }
    )
    
    ;; Initialize milestone task count
    (map-set milestone-task-count
      { project-id: project-id, milestone-id: new-milestone-id }
      { count: u0 }
    )
    
    ;; Update milestone count
    (map-set project-milestone-count
      { project-id: project-id }
      { count: new-milestone-id }
    )
    
    (ok new-milestone-id)
  )
)

;; Create a new task for a milestone
(define-public (create-task 
  (project-id uint) 
  (milestone-id uint) 
  (name (string-ascii 100)) 
  (description (string-utf8 500)) 
  (deadline uint)
  (dependencies (list 10 uint))
)
  (let (
    (task-count-data (default-to { count: u0 } (map-get? milestone-task-count { project-id: project-id, milestone-id: milestone-id })))
    (task-count (get count task-count-data))
    (new-task-id (+ task-count u1))
  )
    ;; Ensure project exists
    (asserts! (is-some (map-get? projects { project-id: project-id })) ERR-PROJECT-NOT-FOUND)
    
    ;; Ensure milestone exists
    (asserts! (is-some (map-get? milestones { project-id: project-id, milestone-id: milestone-id })) ERR-MILESTONE-NOT-FOUND)
    
    ;; Check authorization - admin or team member
    (asserts! (is-authorized project-id ROLE-MEMBER) ERR-NOT-AUTHORIZED)
    
    ;; Verify deadline is in the future
    (asserts! (is-valid-deadline deadline) ERR-INVALID-DEADLINE)
    
    ;; Store task data
    (map-set tasks
      { project-id: project-id, milestone-id: milestone-id, task-id: new-task-id }
      {
        name: name,
        description: description,
        assignee: none,
        deadline: deadline,
        status: STATUS-PENDING,
        dependencies: dependencies
      }
    )
    
    ;; Update task count
    (map-set milestone-task-count
      { project-id: project-id, milestone-id: milestone-id }
      { count: new-task-id }
    )
    
    (ok new-task-id)
  )
)

;; Assign a task to a team member
(define-public (assign-task (project-id uint) (milestone-id uint) (task-id uint) (assignee principal))
  (let (
    (task (unwrap! (map-get? tasks { project-id: project-id, milestone-id: milestone-id, task-id: task-id }) ERR-TASK-NOT-FOUND))
  )
    ;; Ensure project exists
    (asserts! (is-some (map-get? projects { project-id: project-id })) ERR-PROJECT-NOT-FOUND)
    
    ;; Check authorization - admin or current assignee can change assignment
    (asserts! 
      (or 
        (is-authorized project-id ROLE-ADMIN)
        (is-eq (some tx-sender) (get assignee task))
      ) 
      ERR-NOT-AUTHORIZED
    )
    
    ;; Ensure assignee is a team member
    (asserts! (is-some (map-get? team-members { project-id: project-id, member: assignee })) ERR-USER-NOT-FOUND)
    
    ;; Update task assignment
    (map-set tasks
      { project-id: project-id, milestone-id: milestone-id, task-id: task-id }
      (merge task { assignee: (some assignee) })
    )
    
    (ok true)
  )
)