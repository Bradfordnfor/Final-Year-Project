# CHAPTER 1: GENERAL INTRODUCTION

## 1.1 Background and Context of the Study

Every academic year, before lectures begin, each faculty in a university must answer a deceptively simple question: who teaches what, where, and when? Producing that answer is the work of timetabling. A timetable assigns every course to a lecturer, a room, and a period of the week in such a way that no one is asked to be in two places at once. When a faculty has a handful of courses, this can be done on paper over an afternoon. When it has dozens of departments, hundreds of courses, shared lecture halls, lecturers who teach across programmes, and class sizes that outgrow the available rooms, the same task becomes one of the more stubborn administrative problems a university faces.

At the University of Buea, and at the Faculty of Engineering and Technology in particular, this work is still carried out largely by hand. A designated officer collects the list of courses for the semester, notes which lecturer is responsible for each, gathers the available rooms and their capacities, and then tries to fit everything into the fixed periods of the week. The officer works around a long list of rules that are rarely written down anywhere: a lecturer cannot teach two courses at the same time, a class cannot attend two lectures at once, a room cannot host two groups simultaneously, a laboratory session needs a laboratory and not an ordinary hall, and a class of two hundred students cannot be placed in a room that seats eighty. Each of these rules is obvious on its own. The difficulty is that they all apply at the same time, to every assignment, and a choice that satisfies one constraint often breaks another several steps later.

This kind of problem is well known in computer science. The general university timetabling problem belongs to the family of combinatorial scheduling problems and is computationally hard; there is no quick formula that produces a valid timetable, and the number of possible arrangements grows so fast with the size of the faculty that checking them one by one is hopeless even for a computer (de Werra, 1985). Because of this, a person building a timetable by hand does not search for the best possible arrangement. They search for one that simply works, and they usually accept the first one they find, clashes and all.

The consequences are familiar to any student. Timetables are released late. Two compulsory courses for the same class are scheduled in the same period, forcing students to choose which lecture to miss. A class is sent to a room that cannot hold it. A lecturer discovers, on the morning of a class, that the hall is already occupied. When a single change is needed mid-semester, the officer cannot simply edit one entry, because moving one course can create a clash somewhere else, and finding that clash means re-reading the entire timetable. Distribution is no easier: the finished timetable is typically printed, pinned to a notice board, or forwarded informally through messaging groups, so a student who misses the notice board has no reliable way to know their own schedule.

Over the last two decades, universities elsewhere have increasingly turned to software to take over the mechanical part of this work, and the wider shift toward digital administration in Cameroonian higher education makes this an appropriate moment to do the same. A computer does not tire, does not forget a rule halfway through, and can be made to reject any arrangement that violates a hard constraint before a human ever sees it. What it needs is a precise description of the rules and the data, and a method capable of searching the enormous space of possible timetables efficiently. This work sets out to provide exactly that for the university setting: a system that holds all the relevant data in one place, generates a clash-free timetable automatically, routes it through the people who must approve it, and makes the published result easy for students to reach.

## 1.2 Problem Statement

The construction and management of academic timetables at the University of Buea remains a manual, fragmented, and error-prone process. Responsibility for it sits with a small number of staff who must reconcile a large set of competing requirements by hand, without any tool that enforces the rules for them or warns them when a rule has been broken.

Three weaknesses follow from this. First, the process is slow and the output is unreliable. Because a person cannot hold every constraint in mind at once across an entire faculty, the timetables that result frequently contain clashes — a lecturer or a class double-booked, or a course placed in a room that cannot hold it — and these errors are usually discovered only after the semester has begun, when correcting them is most disruptive.

Second, there is no shared system through which the people involved coordinate. A timetable concerns several actors: the officer who builds it, the head of each faculty who is accountable for it, the lecturers whose availability it must respect, and the students who must follow it. In the current arrangement these actors are connected only informally. A draft timetable is not formally reviewed and approved before it takes effect; it is simply circulated. There is no record of who approved what, and no controlled point at which errors can be caught before publication.

Third, the finished timetable is difficult to distribute and to revise. Once published on a notice board or in a messaging group, it cannot easily be filtered so that a particular class sees only its own schedule, and any later change requires the whole document to be regenerated and re-circulated. A student has no dependable, always-current source for their own timetable.

The core problem this work addresses is therefore the absence of an automated, centralised system that can generate a valid, clash-free university timetable from the relevant academic data, coordinate the staff responsible for reviewing and approving it, and deliver the published result to students in a form they can actually use.

## 1.3 Objectives of the Study

### 1.3.1 General Objective

The general objective of this work is to design and implement an automated system that generates conflict-free university timetables and manages their full lifecycle, from the entry of academic data through automatic generation, review, and approval, to publication and distribution to students.

### 1.3.2 Specific Objectives

To achieve the general objective, the work pursues the following specific objectives:

- To model the academic data of a university — its faculties, departments, levels, classes, courses, lecturers, buildings, rooms, and time periods — in a single, structured database that serves as the foundation for scheduling.
- To formulate university timetabling as a constraint satisfaction problem and implement an automatic generator that produces a timetable respecting all hard scheduling constraints, namely the avoidance of lecturer, class, and room clashes, the matching of each course to a suitable type of room, the respect of lecturer unavailability, and the handling of classes that exceed room capacity.
- To design and implement a role-based workflow that allows a timetable officer to submit a generated draft for review, each faculty head to approve or reject the portion concerning their faculty, and the officer to publish only once approval is complete.
- To provide tools for managing the inevitable exceptions, including the resolution of laboratory-splitting conflicts and the manual relocation of an individual session with automatic detection of any clash the change would cause.
- To make the published timetable accessible to students without requiring them to hold an account, through a shareable public view that can be filtered down to a single class.
- To evaluate the resulting system against the manual process it replaces, in terms of correctness, speed, and the coordination it provides.

## 1.4 Proposed Methodology

The work follows an engineering approach organised around the standard stages of software development, adapted to the fact that the central difficulty is not the user interface but the scheduling logic beneath it.

The first stage was requirements analysis. The rules and data of university timetabling were identified by examining how the process is currently carried out and by separating the requirements into those the system must always satisfy (the hard scheduling constraints) and those that describe how it should behave for its users (its functional and non-functional requirements).

The second stage was design. The structure of the system was described using the Unified Modeling Language and an entity–relationship model. An entity–relationship diagram captures the academic data and how its parts relate; use case diagrams describe what each type of user can do; a class diagram describes the software structure; and sequence and activity diagrams describe how the main processes — generating a timetable, approving it, and editing it — unfold over time. These models are presented in Chapter 3.

The third stage was the formulation of the scheduling problem itself. University timetabling was expressed as a constraint satisfaction problem and solved using Google's OR-Tools CP-SAT solver, a constraint-programming engine designed for exactly this class of combinatorial problem. The hard constraints were encoded so that the solver is mathematically prevented from returning any timetable that violates them.

The fourth stage was implementation. The system was built as a client–server application: a backend written in Python using the FastAPI framework, which holds the data, runs the solver, and enforces the rules and permissions; and a cross-platform frontend built with Flutter, through which each type of user interacts with the system. Development proceeded iteratively, building and testing one capability at a time rather than attempting the whole system at once.

The final stage was evaluation, in which the system was exercised with realistic data and its output and behaviour were assessed against the objectives stated above and against the manual process it is intended to replace.

## 1.5 Research Questions

Although this is an engineering project rather than an empirical study, its design was guided by a small number of questions that the work set out to answer:

- How can the academic structure and scheduling rules of a university be represented precisely enough for a computer to generate a valid timetable from them?
- Can a constraint-programming solver produce a clash-free timetable for a realistically sized faculty within a practical amount of time?
- How should responsibility for a timetable be divided among the officer, the faculty heads, lecturers, and students so that the system reflects how the university actually works, while keeping each user's permissions appropriate to their role?
- How can a published timetable be delivered to students who do not hold accounts, in a form that lets each student see only what concerns them?

## 1.6 Significance of the Study

The significance of this work is both practical and technical.

Practically, it offers the University of Buea a direct replacement for a process that is currently slow and unreliable. By enforcing the scheduling rules automatically, the system removes the most common and most disruptive errors — double-bookings and over-capacity placements — before a timetable is ever published. By generating a timetable in minutes rather than days, it frees the responsible staff from work that is mechanical and ill-suited to being done by hand. By routing the draft through a formal approval step, it gives faculty heads a defined point at which to check the timetable concerning their faculty, and it creates a record of who approved it. And by publishing the result to a filterable public page, it gives every student a dependable, current source for their own schedule.

Technically, the work demonstrates the application of constraint programming to a real administrative problem in a Cameroonian university, rather than to a textbook example. It shows how the abstract university timetabling problem can be translated into a concrete model and solved with available open-source tools, and how that solver can be wrapped in a complete system that ordinary staff and students can use. Because the system is designed to hold more than one university, with each university's data kept separate, the approach is not tied to a single institution and can be reused elsewhere.

## 1.7 Scope of the Study

This work covers the generation and management of weekly lecture timetables for a university, together with the administration of the data on which they depend.

Within this scope, the system supports the full academic hierarchy of one or more universities — faculties, departments, levels, and classes — as well as the buildings and rooms in which lectures are held, the lecturers who teach, the courses to be scheduled, and the periods of the week into which they are placed. It supports six categories of user, from a system administrator down to a student, each with permissions appropriate to their role. It generates a complete weekly timetable automatically while respecting the hard scheduling constraints, allows that timetable to be reviewed and approved by the responsible faculty heads before publication, and permits an officer to make controlled manual adjustments afterwards. It handles the practical complications of real scheduling, including courses shared between classes, large classes that must be split into groups for laboratory work, and classes whose size exceeds the capacity of available rooms. Finally, it publishes approved timetables to a public view that students can reach through a shared link and filter down to their own class, and it allows timetables to be exported for printing.

## 1.8 Delimitation of the Study

To keep the work focused and feasible within the time available, several related concerns were deliberately placed outside its boundaries.

The system schedules lecture and laboratory sessions for a normal teaching week; it does not produce examination timetables, which follow a different set of rules and constraints. It does not manage student registration, course enrolment, fee payment, grading, or attendance, and is not intended to be a complete university management system; it concerns itself only with timetabling and the data that timetabling requires. Although the generator respects all hard constraints, it is not designed to optimise soft preferences such as minimising gaps in a lecturer's day or clustering a class's lectures together; its goal is a valid timetable, not a perfected one. The system does not integrate with external biometric or hardware devices, and student access is limited to viewing published timetables, since students in the final design do not hold accounts. These choices narrow the work to a problem that can be solved well rather than a larger one solved superficially.

## 1.9 Definition of Keywords and Terms

**Timetabling.** The process of assigning courses to lecturers, rooms, and periods of the week so that all scheduling rules are respected.

**Constraint Satisfaction Problem.** A problem defined by a set of variables, the values each may take, and constraints restricting the combinations of values allowed; solving it means finding an assignment of values that satisfies every constraint.

**Hard constraint.** A rule that a timetable must never break, such as the rule that a lecturer cannot teach two courses at the same time. An arrangement that violates a hard constraint is invalid.

**CP-SAT.** The constraint-programming solver provided by Google's OR-Tools library, used in this work to search for valid timetables.

**Role-Based Access Control (RBAC).** A method of managing permissions in which each user is given a role, and the actions a user may perform are determined by that role rather than assigned individually.

**Timetable run.** A single generated timetable for a given semester and set of faculties, together with its status as it moves from draft through review and approval to publication.

**Faculty head.** The member of staff accountable for a faculty, who in this system reviews and approves the portion of a timetable concerning their faculty before it is published.

**Class.** A group of students at a particular level of a particular department, treated as a single unit for scheduling and characterised by its student population.

**Room type.** The category of a room — lecture hall, laboratory, or outdoor space — used to ensure that each course is scheduled in a suitable room.

## 1.10 Organization of the Dissertation

This dissertation is organised into five chapters.

Chapter One has introduced the work: the background to university timetabling, the problem it addresses at the University of Buea, the objectives pursued, the methodology adopted, and the scope and significance of the study.

Chapter Two reviews the relevant literature. It presents the key concepts behind automated timetabling, examines the university timetabling problem and the main methods used to solve it, and surveys existing systems and earlier work, drawing out what they contribute and where they fall short.

Chapter Three presents the analysis and design of the system. It states the functional and non-functional requirements, models the data with an entity–relationship diagram, and describes the design through use case, class, sequence, and activity diagrams. It then sets out the global architecture of the solution, the formulation of the scheduling problem, and the algorithm used to generate timetables.

Chapter Four describes the implementation and presents the results. It details the tools and technologies used, explains how the system was built, presents the working system through screenshots of its main features, and evaluates the solution against the objectives and against the manual process it replaces.

Chapter Five concludes the work. It summarises what was achieved, states the contribution to engineering and technology, offers recommendations, records the difficulties encountered, and suggests directions for further work.
