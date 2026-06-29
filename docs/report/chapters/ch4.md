# CHAPTER 4: IMPLEMENTATION AND RESULTS

## 4.1 Introduction

Chapter 3 set out what the system should be: a data model faithful to the structure of a Cameroonian university, a constraint model that enforces the hard scheduling rules by construction, and a workflow that places a generated timetable before the people accountable for it before it reaches a student. This chapter describes how that design was turned into working software, shows the result, and judges it against the goals it was built to serve.

It is organised to follow the design into reality. It first records the tools and materials used to build the system — the languages, frameworks, libraries, and environment on which the work rests. It then describes the implementation process itself, moving through the system as it was constructed: the data layer, the application interface and its access control, the scheduling engine at the centre, the coordination workflow that surrounds it, and the client application through which users meet all of it. The chapter then presents the working system through screenshots of a realistic case study drawn from the Faculty of Engineering and Technology, interpreting what each shows, and evaluates the solution against the manual process it replaces, against the objectives stated in Chapter 1, and against the correctness it was required to guarantee. A partial conclusion closes the chapter.

The account given here is faithful to the system as built. Where the implementation departed from the first design, or where building a part revealed something the design had not anticipated, that is recorded rather than smoothed over, because it is in those departures that the practical lessons of the work lie.

## 4.2 Tools and Materials

The system was built almost entirely from open-source components, a decision that follows directly from the portability requirement of Chapter 3: a university should be able to deploy the system without paying for proprietary licences. The choices were also guided by fitness for the specific problem — above all the availability of a capable constraint solver — and by the goal of serving the web and mobile from a single effort.

### 4.2.1 Hardware and Development Environment

Development was carried out on a standard personal computer running Windows, with the code written and managed in Visual Studio Code. Version control was handled with Git, the work progressing on feature branches that were merged once each slice was complete and tested. No specialised or high-performance hardware was required: the constraint solver runs comfortably on an ordinary machine for instances of the size a single faculty produces, which is itself a point in the system's favour, since it can be hosted modestly.

### 4.2.2 Backend Technologies

The server is written in **Python 3.13**, chosen for its clarity and, decisively, for its access to mature optimisation libraries. Its principal components are summarised in Table 4.1.

The web framework is **FastAPI**, which exposes the system's functions as a REST interface over HTTP and validates every request and response against typed schemas defined with **Pydantic**. The application is served by the **Uvicorn** ASGI server. Persistence is handled by **SQLAlchemy 2.0**, an object–relational mapper that maps the domain classes onto database tables, with **Alembic** managing changes to the database schema over the life of the project. The database itself is **SQLite** in the development configuration, chosen for the simplicity of needing no separate server; because access goes through the ORM, a larger database engine can be substituted without changing the application code.

The scheduling engine is built on **Google OR-Tools** (version 9.15) and its CP-SAT constraint solver, the component that does the actual work of finding a valid timetable. Authentication uses JSON Web Tokens, issued and verified with **python-jose**, while passwords are hashed with **passlib** over the **bcrypt** algorithm, so that no password is ever stored in readable form. Timetables are rendered to PDF for printing with **ReportLab**. The automated tests are written with **pytest**.

> **Table 4.1** — Backend tools and their role in the system.

| Tool / Technology | Version | Role in the system |
|---|---|---|
| Python | 3.13 | Implementation language of the server |
| FastAPI | — | Web framework exposing the REST/JSON interface |
| Pydantic | 2 | Validation of request and response data |
| Uvicorn | — | ASGI server that runs the application |
| SQLAlchemy | 2.0 | Object–relational mapping to the database |
| Alembic | — | Database schema migrations |
| SQLite | 3 | Database (development configuration) |
| Google OR-Tools (CP-SAT) | 9.15 | Constraint solver at the heart of generation |
| python-jose | — | Issuing and verifying JWT authentication tokens |
| passlib + bcrypt | — | One-way hashing of passwords |
| ReportLab | — | Rendering timetables to PDF |
| pytest | — | Automated testing |

### 4.2.3 Frontend Technologies

The client is built with **Flutter** and the **Dart** language, from a single codebase that compiles to both the web and mobile devices — the means by which the portability and usability requirements are met at once. State management, routing, and dependency injection are handled with **GetX**, keeping the application's moving parts loosely coupled. Communication with the server uses the **Dio** HTTP client, and authentication tokens are held on the device in **flutter\_secure\_storage** rather than in ordinary storage. The interface is built from **Material 3** components, typeset in the **Inter** typeface supplied through **google\_fonts**, with charts drawn by **fl\_chart** and small transitions by **flutter\_animate**. These are listed in Table 4.2.

> **Table 4.2** — Frontend tools and their role in the system.

| Tool / Technology | Version | Role in the system |
|---|---|---|
| Flutter | 3.22+ | UI framework for web and mobile from one codebase |
| Dart | 3 | Implementation language of the client |
| GetX | — | State management, routing, dependency injection |
| Dio | — | HTTP client for calling the server |
| flutter\_secure\_storage | — | Secure storage of authentication tokens |
| fl\_chart | — | Charts on the analytics dashboard |
| google\_fonts (Inter) | — | Typography |
| flutter\_animate | — | Interface transitions |

### 4.2.4 Modelling and Documentation Tools

The diagrams of Chapter 3 — the entity–relationship, use case, class, sequence, and activity diagrams — were written as **PlantUML** source and rendered to images, so that they could be kept under version control and revised as text alongside the code they describe.

## 4.3 Description of the Implementation Process

The system was not built top to bottom in one pass. As Section 3.2 explained, it was built in slices, each a thin but working path through the whole stack, with the riskiest part — the scheduling engine — tackled and proven first. This section describes the result of that process by layer, in the order the layers depend on one another, noting along the way the points at which building the system taught something the design had not foreseen.

### 4.3.1 Project Organisation

The code is divided into two independent projects, a `backend` and a `frontend`, that meet only at the REST interface. Within the backend, responsibilities are kept in separate packages: the `models` define the data, the `schemas` define the shapes of requests and responses, the `routers` handle incoming calls, the `core` holds cross-cutting concerns such as authentication and access control, and the `solver` holds the scheduling engine, deliberately set apart from everything that knows about the database or the web. This division is not cosmetic; it is what allows the scheduling engine to be tested in isolation and the rest of the system to be reasoned about a piece at a time.

### 4.3.2 The Data Layer

The first layer built was the data, since everything rests on it. Each entity of the model in Section 3.4.1 is implemented as a SQLAlchemy class — `University`, `Faculty`, `Department`, `Level`, `Class`, `ClassGroup`, `Building`, `Room`, `Semester`, `TimeSlot`, `Course`, `User`, `Lecturer`, `Student`, and the timetable-run family of `TimetableRun`, `TimetableEntry`, `TimetableConflict`, `GenerationJob`, `FacultyHeadApproval`, and `Notification` — with the relationships between them expressed as foreign keys and navigable associations. The many-to-many relationships that the relational model cannot hold directly are carried by link tables: `SharedCourse` records which extra classes attend a shared course, `TimetableEntryClass` records the classes attending each session, and `TimetableRunFaculty` and `TimetableRunBuilding` record the scope of a run. Schema changes over the life of the project were managed with Alembic migrations. To make development and testing convenient, a seed script was also written to populate a database with a small sample of representative data — a university, a faculty with two departments, a building with a couple of rooms, a semester of time slots, and one account for each role — so that the system could be run without entering data by hand. This sample is a development convenience only; the evaluation of Section 4.4 uses the real academic data of the faculty, not the seed.

Each course also carries the semester of study it belongs to (first, second, or year-long) and each semester record its term, so that generation can be scoped to one semester at a time rather than scheduling a level's whole year at once.

A point worth recording is that the single `User` table carries not only the credentials and role of every account-holder but also the institutional links — university, faculty, department — that later proved essential to scoping what each user may see and do. A faculty head, for instance, is an ordinary user whose `faculty_id` ties them to the one faculty they govern; that single field is what later distinguishes the head of Engineering from the head of any other faculty.

### 4.3.3 The Application Interface and Access Control

On top of the data sits the REST interface, implemented as a set of FastAPI routers grouped by concern: universities, faculties and departments, rooms and buildings, semesters and time slots, courses, users, the faculty-setup tree, the timetable runs, and the exports. Each incoming request is validated against a Pydantic schema before it reaches any logic, so that malformed data is rejected at the boundary rather than deep inside the system.

Access control is enforced at this layer and on the server alone, never left to the client. Authentication is by signed JWT: a successful login returns a token that the client attaches to every later request, and a dependency on each protected route decodes the token, loads the user, and confirms the account is active. Authorisation is layered over this through a set of role dependencies — a hierarchy in which a super administrator may act anywhere, a university administrator within their university, a faculty head over their faculty's academic data, and a timetable officer over the runs — so that a request carrying a valid token but an insufficient role is refused. Two facets of this access control were strengthened during implementation once their importance became clear in use. First, the faculty-setup routes resolve a non-administrative user to their own faculty automatically and reject any attempt to reach another's, so that the head of one faculty cannot read or alter another's departments and courses. Second, the listing of timetable runs was scoped so that a faculty head is shown only the runs that touch their own faculty. That listing is also scoped by status: a draft is returned only to the officer and the administrators, while a faculty head and a lecturer receive a run only once it is under review or published, so a timetable in progress stays private until it is ready to be seen. The analytics endpoint is scoped in the same spirit — it is refused to the officer, returns the whole run to an administrator, and narrows to a single faculty's sessions for that faculty's head. Together these turn the institutional links recorded on the `User` into real separation of one faculty's work from another's.

### 4.3.4 The Scheduling Engine

The scheduling engine was, by design, the first thing built and the part proven before any interface existed around it. It is implemented in three stages that pass plain data structures between them, none of which knows about the database or the web.

The preprocessor reads the courses of the faculties in a run and turns them into the list of *sessions* the solver must place, making the decisions described in Section 3.6.1: merging a shared course into a single session when the combined population of its classes fits the largest suitable room within the university's overflow threshold, and splitting a laboratory class into as many groups as the largest available laboratory will hold. University-wide courses are handled here too: since every class takes them, the preprocessor packs the classes into as few hall-sized groups as the overflow threshold allows, so that several classes sit a requirement together rather than the lecturer repeating it for each. A course marked as held off-site is recognised as needing no room, and its sessions are built to be placed by time alone. Where a laboratory needs more groups than the week has sessions, the preprocessor does not force an answer; it records a conflict for an officer to resolve later.

The solver stage encodes the problem for OR-Tools CP-SAT exactly as Section 3.6.2 describes. For each legal combination of session, time slot, and room it creates a boolean variable, then adds the hard constraints as conditions over those variables — that each session is placed exactly once, that no room, lecturer, or class is double-booked, that a session occupies only a room of the type it requires, and that no session falls in a slot its lecturer has declared unavailable. Room capacity is handled as the design prescribed: rather than forbidding an over-full room, which the shortage of large halls would often make fatal, the model permits the placement and flags the resulting entry, so that crowding is made visible rather than hidden.

Two refinements proved necessary once the engine met real data. The first concerns off-site courses, which need no room: to keep the uniform session–slot–room model intact, each such session is given a private placeholder room of its own, which the postprocessor later discards so that the entry is stored with no room at all. The second is the objective. Because the hard constraints alone admit many equally legal timetables — including ones that hand a large hall to a tiny class while a joint course overflows a small room — the model is given a cost to minimise: every placement is charged the seats it leaves empty, and a room too small for its session is charged a heavy penalty, so the solver is steered to put the large and joint sessions in the large halls and the small classes in the small rooms. With the objective in place the solver is given a bounded time and returns either a valid assignment — optimal where it could prove so, otherwise feasible — or a clear statement that none exists.

Because the search can take longer than a web request should be held open, generation does not run inside the request that asks for it. The request records a `GenerationJob`, schedules the work as a background task, and returns at once; the client then polls the job's status until it completes or fails. When the solver succeeds, the postprocessor writes its assignments back into the database as `TimetableEntry` rows, linking each to the classes that attend it and flagging those that are over capacity or merged. When it fails — or when there were no sessions to place at all — the job records the reason, so that a failure leaves an explanation rather than an unexplained silence.

### 4.3.5 The Coordination Workflow

Around the engine sits the workflow that carries a timetable from a request to a published schedule, implemented as a small state machine on the `TimetableRun`. A run begins as a *draft*. An officer may generate into it as often as needed — each generation first clears the previous result, so a regeneration replaces the draft rather than stacking a second timetable on top of it — then submit it for review, which moves it to *under review*; when every faculty head has approved their section it becomes *approved*; and only an approved run may be *published*. A single rejection sends the run back to draft with the head's comment attached, for the officer to correct and resubmit. Each transition is guarded so that it can only happen from the state that should precede it, and each fires the notifications that keep the people concerned informed.

One guard added during implementation deserves particular mention, because it closes a gap the first design left open. Generation was originally triggered by little more than a check that the run was a draft, which meant the engine could be set to work on data that could not possibly yield a timetable — a run whose courses had no lecturers, or whose buildings held no suitable rooms, or whose semester had no time slots. In the worst case it would complete with an empty result that wore the appearance of success. A readiness check was therefore introduced ahead of generation. It inspects the run exactly as the preprocessor will — the same faculty-to-course and building-to-room scoping — and confirms that the run has faculties and buildings, that the buildings hold active rooms, that the semester has time slots, that the faculties contain classes to be taught and courses to schedule, that every course has a lecturer, and that a room exists for every room type the courses require — off-site courses, which need none, aside. If anything is missing, generation is refused with a checklist naming precisely what must be fixed, and the same checklist is shown in the interface so the officer is never left guessing. One item on that list earned its place only in use: a faculty set up with no departments or classes was found to pass every other check, because its scope still drew in the university-wide courses that every student takes — courses with lecturers and room requirements of their own — which lent the empty faculty the look of readiness when there was in truth not a single class to attend them. The requirement that a run's faculties hold classes at all was added to catch exactly that. This makes concrete, at the point of generation, the correctness principle that runs through the whole design: the system should refuse to produce a result it cannot stand behind.

Submission for review is guarded in the same spirit. Before a run can be submitted, the system confirms that every faculty it covers has an active head to approve it, since there is no sense in requesting an approval that no one is in a position to give.

### 4.3.6 The Client Application

The client was built once the interface it consumes was stable, as a single Flutter application that adapts to the device it runs on. A shell arranges the screens behind a persistent sidebar on a wide desktop display, a compact navigation rail on a medium screen, and a bottom navigation bar on a phone, so that the same application is usable at a staff member's desk and in a student's hand. State, routing, and the construction of the API clients are managed through GetX, and all communication with the server passes through a single typed client built on Dio, which attaches the authentication token to every call.

The screens follow the roles rather than the database. After logging in, a user reaches a dashboard whose contents depend on their role; from there an administrator reaches the management screens for buildings, users, semesters, and courses, and a faculty head reaches the faculty-setup tree of departments, levels, classes, courses, and groups. The timetable screen lists the runs and presents a selected one as a weekly grid, with the controls to generate, submit, approve, publish, filter, and edit it, and it is here that the readiness checklist and the generation progress appear. A separate conflicts screen resolves the problems flagged during preprocessing. Finally, the published timetable is exposed on a public page that needs no account and is reached through a shareable link, which a visitor narrows to a single class with a faculty–department–level filter — the path by which a student, who holds no account by design, reaches their own schedule.

### 4.3.7 Testing

Testing accompanied the construction rather than following it. The scheduling engine was tested first and in isolation, against small instances whose correct answers could be checked by hand, so that the central assumption of the project — that a constraint solver could express the rules of university timetabling and return a usable answer — was validated before effort was spent around it. As each later slice was added, automated tests were written for it with pytest, exercising the API through a test client against a temporary database: the creation and management of the academic data, the rules of access control, the lifecycle of a run, the readiness check that guards generation, the manual relief of over-crowded sessions, the bulk import together with its preview and its handling of an unreadable file, and the requirement that a faculty head be bound to a faculty. These tests served not only to confirm that each part worked when written but to catch the regressions that inevitably arise when a later change disturbs an earlier assumption.

## 4.4 Presentation and Interpretation of Results

To show the system working as a whole rather than feature by feature, it was exercised on a realistic case study: the timetable of the Faculty of Engineering and Technology (FET) for the first semester of the 2025/2026 session. The faculty's real academic data was entered — its four departments of Computer, Electrical, Civil, and Mechanical Engineering, the levels and classes within them, the courses each runs in the semester, and the lecturers who teach them — and a run was created scoped to the faculty's buildings and the semester's weekly periods. The instance is not a toy. It comprises thirteen classes, eighty-nine courses, and forty-five lecturers, to be placed across the faculty's lecture halls and laboratories in the thirty-four teaching periods of the week. What follows traces the system through the case study screen by screen and then reports the figures the run produced.

### 4.4.1 Entering the academic data

The starting point is the academic data on which everything else depends. An administrator sets up the university's faculties, departments, levels, and classes, its buildings and rooms, and its semesters and time slots, and records the courses each level runs together with the lecturer who teaches each (Figure 4.1). Entering forty-five lecturers by hand would be tedious, so they were created in a single step from a spreadsheet through the bulk import, which matches each row's faculty and department by name within the administrator's own university. Because the wrong file, or one with the wrong columns, could otherwise create dozens of accounts that then had to be hunted down and undone, the import does not write on contact: it first shows a preview — the rows it would create and those it would skip, each with the reason it was skipped — and commits nothing until the administrator confirms it (Figure 4.2). A file that is not readable as a CSV at all is met with a plain explanation rather than a raw error. A course with no lecturer cannot be scheduled, so the courses screen offers a filter that shows at a glance which courses still need one, turning a hidden gap into a short, visible to-do list (Figure 4.3).

> **Figure 4.1** — Management of courses, showing each course with its assigned lecturer. (Screenshot.)

> **Figure 4.2** — Bulk import of lecturers from a CSV, with the generated credentials listed once. (Screenshot.)

> **Figure 4.3** — The courses screen with the "needs lecturer" filter active. (Screenshot.)

### 4.4.2 The readiness check

When the officer asks to generate, the system first checks that the run can actually yield a timetable. If something is missing — a course without a lecturer, a semester without time slots, buildings without suitable rooms — generation is refused and a checklist names precisely what must be fixed (Figure 4.4), so the officer is never left guessing at an empty or failed result. Once every item is satisfied the same run is ready, and generation proceeds (Figure 4.5).

> **Figure 4.4** — The readiness checklist refusing generation, with the failing items marked. (Screenshot; produced from a deliberately incomplete run.)

> **Figure 4.5** — A run that passes every readiness check, ready to generate. (Screenshot.)

### 4.4.3 Generation and the weekly grid

Generation does not block the interface: the request returns at once and the officer sees a progress indicator while the solver works in the background (Figure 4.6). For the FET instance the solver returned an **optimal** assignment in about **thirty-two seconds**, placing **185 sessions**. The result is presented as a weekly grid, which can be narrowed with the class filter to a single class, a department, or the whole faculty (Figure 4.7). Sessions serving several merged classes, placements that exceed a room's capacity, and off-site sessions that occupy no room are each marked, so the officer can see at a glance where the result needed compromise.

> **Figure 4.6** — Generation in progress, with the background-job indicator. (Screenshot.)

> **Figure 4.7** — The generated weekly timetable for a class, with the class filter. (Screenshot.)

### 4.4.4 Conflicts and their resolution

Not every difficulty can be solved silently. The case-study run raised **four laboratory-splitting conflicts** — classes too large for any laboratory to take in the sessions the week allows — which the system flags rather than forcing a bad answer (Figure 4.8). The officer settles each, choosing either to add an extra weekly session or to rotate the groups across alternating weeks, and the conflict then disappears from the list.

> **Figure 4.8** — The conflicts screen listing the flagged laboratory-split conflicts and the two resolution options. (Screenshot.)

### 4.4.5 Review, approval, and publication

A generated draft does not take effect on its own. The officer submits it for review, and each faculty head whose faculty the run touches is asked to approve the portion concerning them; the run cannot advance until every head has approved, and a single rejection returns it to the officer with a comment (Figure 4.9). Only once approval is complete may the officer publish it. The published timetable is then exposed on a public page that needs no account and is reached through a shareable link; a student opens it, narrows it to their own class, and sees their schedule and nothing else (Figure 4.10).

> **Figure 4.9** — The approval panel of a run under review, as a faculty head sees it. (Screenshot.)

> **Figure 4.10** — The public student view, filtered to a single class. (Screenshot.)

### 4.4.6 The figures the run produced

Table 4.3 gathers the quantities from the case-study run. Three of them deserve a word of interpretation. First, the generator scheduled three **university-wide courses** — the general requirements every student takes — packing the thirteen classes into shared hall-sized sessions rather than repeating each lecture class by class. Second, **thirty-two** of the sessions are merged, each serving more than one class at once, which is what keeps the total number of sessions, and the lecturers' load, down. Third, **nine** placements exceed their room's capacity: not a failure of the solver but a faithful report of a real shortage of large halls, made visible rather than hidden, as Section 4.5 discusses.

> **Table 4.3** — Figures produced by the FET case-study run (first semester, 2025/2026).

| Quantity | Value |
|---|---|
| Solver status | Optimal |
| Solve time | ≈ 32 seconds |
| Sessions placed | 185 |
| Courses scheduled | 89 (3 university-wide) |
| Classes covered | 13 |
| Lecturers scheduled | 45 |
| Rooms used | 8 |
| Weekly periods used | 34 |
| Merged (multi-class) sessions | 32 |
| Off-site sessions (no room) | 2 |
| Over-capacity placements | 9 |
| Laboratory-split conflicts flagged | 4 |
| Lecturer / class / room clashes | 0 / 0 / 0 |

## 4.5 Evaluation of the Solution

The system is now judged against what it was built to do: the specific objectives of Chapter 1, and the manual process it is meant to replace, on the three grounds the final objective names — correctness, speed, and coordination.

### 4.5.1 Correctness

Correctness was the foremost requirement, and it is the clearest result. The output of the case-study run was checked, session by session, against the hard rules: across all 185 placements there were **no lecturer double-bookings, no class double-bookings, and no room double-bookings**, every session sat in a room of the type its course required, and no session fell in a period a lecturer had declared unavailable. This is not a fortunate outcome of one run but a property of the method: as Section 3.6 argued, the solver cannot return an assignment that breaks a hard constraint, because such assignments are excluded from its search by construction. Set against the manual process of the problem statement — where a planner cannot hold every constraint in mind at once, and clashes typically surface only after the semester has begun — this is the central improvement the work offers.

### 4.5.2 Use of scarce rooms

The handling of room capacity is worth singling out, because it shows the objective doing real work. The solver returned an *optimal* result, meaning the nine over-capacity placements are not an oversight but the fewest the faculty's halls allow: there is simply no room large enough for those classes, and the system accepts the crowding only where it is unavoidable and flags it for the officer. The value of the objective is seen by comparison. The same data, generated before the room-fit objective was added, produced **forty-five** over-capacity placements, because rooms were assigned with no regard to fit — small classes could fall into large halls while large classes overflowed small rooms. Introducing the objective reduced this to the nine that are genuinely forced by the shortage of halls, reserving the large rooms for the large and joint sessions that need them. Where even those nine trouble the officer, the model's verdict is not the last word: as Section 3.7 describes, a class can be taken out of a crowded session into one of its own, or gathered onto a hall already teaching the same course with the same lecturer — the same scarce-room arithmetic applied a second time, by hand, where local knowledge suggests a better compromise than the solver could see.

### 4.5.3 Speed

The generator placed 185 sessions for an entire faculty in about thirty-two seconds. The manual construction of a faculty timetable is, by contrast, the work of days, repeated whenever a change forces a rebuild. Beyond the raw figure, the difference in kind matters: a thirty-second generation can be run again and again as data is corrected or constraints are adjusted, where a manual timetable is too costly to redo and so tends to be patched rather than regenerated.

### 4.5.4 Coordination

The second weakness of the problem statement — the absence of any shared system through which the responsible staff coordinate — is answered by the workflow. In the case study the run moved from draft, through review, to approval, and only then to publication, with each faculty head approving the portion that concerned them and the approvals recorded against the run. Where the manual process circulates a draft informally and keeps no record of who approved what, the system makes the review a controlled gate that a timetable must pass before it can reach a student, and a published timetable is therefore one for which accountability has been established and stored.

### 4.5.5 Against the existing tools

This places the system against the tools surveyed in Chapter 2. Those tools generate competent timetables, and the generator here does not claim to surpass mature engines such as UniTime at the solving task alone. What they do not do is coordinate the people accountable for a timetable or deliver it to students: they are single-planner, desktop-bound tools that produce a file. The contribution of this work is to wrap a capable constraint solver in the workflow and the student-facing distribution that a Cameroonian faculty actually needs, around a data model shaped to the faculty–department–level structure those tools do not assume.

### 4.5.6 Against the objectives

Table 4.4 sets the specific objectives of Section 1.3.2 against the evidence of the case study.

> **Table 4.4** — The specific objectives of Chapter 1 and the evidence that each is met.

| Specific objective | Outcome |
|---|---|
| Model the academic data in a single structured database | Met — the faculty's full hierarchy, rooms, semesters, and courses were entered and drove the run (§4.3.2, §4.4.1). |
| Formulate timetabling as a constraint problem and generate respecting all hard constraints | Met — an optimal, clash-free timetable of 185 sessions was generated (§4.4.3, §4.5.1). |
| A role-based review-and-approval workflow | Met — the run passed draft → review → approval → publication, with recorded approvals (§4.4.5). |
| Tools for exceptions: conflict resolution, clash-checked manual moves, and relief of crowded sessions | Met — four laboratory conflicts were resolved by the officer, manual moves are checked for clashes before acceptance, and a class may be taken out of an over-capacity merged session or gathered onto a hall teaching the same course (§4.4.4, §4.3.5, §3.7). |
| A student-accessible public view, filterable to one class, without an account | Met — the published run is reachable by link and narrowed to a class (§4.4.5). |
| Evaluate against the manual process | Met — this section, on correctness, speed, and coordination. |

### 4.5.7 Limitations

Honesty requires that the limits be stated alongside the results. The evaluation is a demonstration on a single faculty's data, not a controlled study with users; it shows that the system does what it was specified to do, not how staff would take to it over a term. The generator models the hard constraints but not soft preferences — a lecturer's preferred, as opposed to impossible, times, or a faculty's wish to cluster a class's lectures in the morning — so its timetables are valid but not tuned to taste. And while the FET instance was solved to proven optimality within the time bound, a larger run spanning several faculties at once may reach only a *feasible* solution before the bound is hit; the result would still be valid, but not guaranteed to be the best possible use of rooms. None of these undoes the core result, but each marks where the work could go further, as Chapter 5 takes up.

## 4.6 Partial Conclusion

This chapter has carried the design of Chapter 3 into a working system and judged it. It set out the tools the system is built from and the reasons for choosing them, then described the implementation layer by layer — the data, the access-controlled interface, the three-stage scheduling engine, the coordination workflow, and the adaptive client — recording where building the system taught something the design had not foreseen. It then exercised the whole system on a realistic case study, the first-semester timetable of the Faculty of Engineering and Technology, and presented the result: an optimal, clash-free timetable of 185 sessions generated in about thirty-two seconds, carried through review and approval to a published, student-accessible schedule. Measured against the objectives of Chapter 1, the system meets each; measured against the manual process it replaces, it offers correctness by construction, generation in seconds rather than days, and a recorded chain of accountability the manual process lacks. The limitations that remain — the absence of soft preferences, and the optimality not guaranteed for the largest instances — are the natural starting points for the work that the final chapter recommends.
