# CHAPTER 2: LITERATURE REVIEW

## 2.1 Introduction

The problem of building a university timetable is older than the computers now used to solve it, and it has been studied seriously by researchers in operations research and computer science for more than half a century. Before designing a new system, it is worth understanding what that body of work has established: what kind of problem timetabling actually is, why it is hard, the main families of methods that have been used to attack it, and what existing software already offers. This chapter sets out that background.

The chapter begins with the general concepts behind automated timetabling — the structure of the problem, the distinction between the different kinds of educational timetabling, the central idea of constraints, and the broad approaches that have been developed to find solutions. It then reviews related work, looking both at the methods reported in the research literature and at the timetabling systems already in use, and draws out what they offer and where they leave gaps. The chapter closes by positioning the present work against this background.

## 2.2 General Concepts on Automated Timetabling

### 2.2.1 The Timetabling Problem

In its most general form, a timetabling problem is the task of placing a set of events into a limited number of time periods and resources, subject to a collection of constraints (Wren, 1996). In the educational setting, the events are lectures or examinations, the time periods are the slots of a week or an examination season, and the resources are the rooms and the people — lecturers and students — involved. A solution is an assignment of every event to a period and a resource such that no constraint is broken.

The difficulty of the problem comes from the interaction of its constraints. de Werra (1985) showed that timetabling can be expressed naturally in the language of graph colouring, where events are represented as the vertices of a graph, an edge joins any two events that cannot share a period, and a valid timetable corresponds to a colouring of the graph in which no two adjacent vertices receive the same colour. This connection is important because graph colouring is known to be NP-complete, and the timetabling problems that reduce to it inherit that hardness. Even, Itai, and Shamir (1976) proved directly that even restricted versions of the timetable problem are NP-complete. The practical meaning of this result is that there is no known algorithm guaranteed to find a valid timetable quickly for every input; as the number of events and constraints grows, the number of possible arrangements grows exponentially, and the search for a valid one cannot be reduced to a simple procedure.

### 2.2.2 Types of Educational Timetabling

The research literature distinguishes three broad categories of educational timetabling, which differ enough that methods suited to one are not always suited to another (Schaerf, 1999).

**School timetabling** concerns the weekly schedule of a school, in which classes of pupils are fixed groups that stay together and teachers move between them. The defining feature is that each class has a settled membership, so the main task is to assign teachers and rooms to class–period pairs.

**Course timetabling**, sometimes called university timetabling, concerns the lectures of a university. Here the situation is more fluid than in a school: courses may be shared between programmes, students may belong to several groupings at once, and lecturers often teach across departments. This is the category into which the present work falls.

**Examination timetabling** concerns the scheduling of examinations rather than lectures. Although it resembles course timetabling, it is governed by different rules — for example, that a student should not sit two examinations at the same time, and ideally should not sit several in immediate succession — and is usually treated as a separate problem (Carter, Laporte, & Lee, 1996).

The system developed in this work addresses course (university) timetabling; examination timetabling is deliberately left outside its scope, as stated in Chapter 1.

### 2.2.3 Hard and Soft Constraints

A constraint is a rule that restricts which assignments are allowed. The literature draws a fundamental distinction between two kinds (Burke & Petrovic, 2002).

**Hard constraints** are rules that a timetable must never break. A timetable that violates even one hard constraint is not merely poor but invalid and unusable. In university timetabling the standard hard constraints are that a lecturer cannot be assigned to two events in the same period, that a class cannot attend two events in the same period, that a room cannot host two events in the same period, that an event must be placed in a room suited to it, and that a room's capacity must not be exceeded.

**Soft constraints** are preferences whose satisfaction makes a timetable better but whose violation does not make it invalid. Examples include avoiding gaps in a lecturer's day, spreading a class's lectures evenly across the week, or honouring a lecturer's preferred periods. The quality of a timetable is usually measured by how few soft constraints it violates.

This distinction shapes how the problem is solved. Finding any timetable that satisfies all hard constraints is itself difficult; finding one that also satisfies as many soft constraints as possible is harder still. Many systems therefore treat the two separately, first securing validity and then improving quality. The present work concentrates on hard constraints: its aim is to produce a valid, clash-free timetable reliably, rather than an optimised one.

### 2.2.4 Approaches to Solving the Problem

Over the decades, several families of methods have been applied to educational timetabling. They can be grouped as follows.

**Graph-based and sequential heuristics** were among the earliest approaches. Building on de Werra's graph-colouring formulation, these methods place events one after another, each time choosing the event that is hardest to place and giving it a period that breaks no constraint. They are fast and simple but can paint themselves into a corner, reaching a point where some remaining event cannot be placed at all.

**Constraint programming and constraint satisfaction** treat timetabling directly as a constraint satisfaction problem: the events are variables, the periods and rooms are the values they may take, and the rules are constraints that the assignment must satisfy. A constraint solver searches this space systematically, using the constraints themselves to prune away large regions that cannot contain a valid solution. This is the approach taken in the present work, using Google's OR-Tools CP-SAT solver (Perron & Furnon, 2019).

**Mathematical programming** formulates timetabling as an integer or mixed-integer linear program and solves it with general optimisation techniques. This approach can find provably optimal solutions for smaller instances but tends to scale poorly as the problem grows.

**Metaheuristics** are general-purpose search strategies that explore the space of possible timetables by repeatedly modifying a candidate solution in search of improvement. Simulated annealing was applied to school timetabling by Abramson (1991); tabu search, genetic and evolutionary algorithms (Colorni, Dorigo, & Maniezzo, 1990), ant colony optimisation, and memetic algorithms have all been used. These methods do not guarantee a valid solution but often perform well on large, heavily constrained instances.

**Hybrid and hyper-heuristic methods** combine several of the above, or operate at a higher level by choosing which heuristic to apply at each step. Burke and Petrovic (2002) identified these as a promising direction precisely because no single method dominates across all timetabling problems.

The International Timetabling Competition, organised in 2002, 2007, and 2019, has been influential in comparing these approaches on common benchmark problems and has driven much of the recent progress in the field. The choice of constraint programming for the present work reflects its natural fit with the problem: the hard scheduling rules translate almost directly into constraints, and a modern solver such as CP-SAT can enforce them exactly, returning either a valid timetable or a clear indication that none exists.

## 2.3 Related Works

### 2.3.1 Methods Reported in the Literature

A large body of research has applied the methods described above to real and benchmark timetabling problems. Schaerf (1999) provided an early and widely cited survey of the field, organising the methods and the problem variants and establishing much of the vocabulary still used today. Burke and Petrovic (2002) reviewed the directions research was taking and argued for hybrid and knowledge-based approaches. Carter, Laporte, and Lee (1996) surveyed examination timetabling specifically and reported on practical systems deployed at universities.

Among constraint-based and solver-based work, the UniTime project, developed by Müller and collaborators, stands out as a sustained effort to apply constraint solving to real university timetabling at scale; it grew out of the International Timetabling Competition and is used by a number of universities. Metaheuristic approaches are represented by Abramson's (1991) application of simulated annealing and by the evolutionary methods of Colorni, Dorigo, and Maniezzo (1990), among many others.

What this literature establishes is that automated university timetabling is both achievable and well studied, that constraint programming is a sound and well-supported choice of method, and that the largest remaining challenges are less about whether a valid timetable can be produced than about how a complete, usable system can be built around the solver for a particular institutional setting.

### 2.3.2 Existing Timetabling Systems

Several software systems for educational timetabling are already available, ranging from free open-source tools to commercial packages.

**UniTime** is a comprehensive, open-source university timetabling system that uses a constraint solver to generate course and examination timetables and supports the distribution of timetabling work across departments. It is powerful and proven, but it is also large and complex to deploy and configure, and it assumes an institutional structure and an administrative process modelled on the North American and European universities for which it was developed.

**FET (Free Evolutionary Timetabling)** is a free, open-source application that generates timetables using a heuristic algorithm. It is capable and widely used, particularly for schools, but it runs as a desktop application operated by a single user, and it offers no notion of multiple roles, no review-and-approval workflow, and no built-in means of distributing the finished timetable to students.

**aSc Timetables** is a long-established commercial package for school timetabling, known for an accessible interface and strong manual-editing tools. It is, however, proprietary and paid, oriented toward the school rather than the university model, and likewise desktop-based and single-operator.

**Other tools**, such as Lantiv Timetabler and Mimosa Scheduling Software, occupy similar ground: they generate timetables competently but are generally desktop applications aimed at a single planner, with little support for the multi-actor coordination that a university faculty involves.

Taken together, these systems show that timetable generation is a solved problem in the narrow sense — good tools exist for producing a schedule. What they tend to share, however, are limitations that matter in the setting this work addresses. Most are built around a single operator working on a desktop, rather than around the several actors — officer, faculty heads, lecturers, students — who are involved in a real university timetable, and so they provide no formal review-and-approval step and no record of who approved a timetable. Most assume an institutional structure that does not match the faculty–department–level hierarchy of a Cameroonian university. The capable ones are often either costly or demanding to set up. And few give any attention to the last step that matters most to students: getting the published timetable into their hands in a form they can filter down to their own class, without requiring every student to hold an account.

## 2.4 Partial Conclusion

This review has shown that university timetabling is a well-defined and well-studied problem, computationally hard in general but tractable in practice through a number of established methods, of which constraint programming is among the most natural and best supported. It has also shown that while capable timetable-generating software already exists, the available systems are largely built for a single planner working in isolation, assume institutional structures that do not fit a Cameroonian university, and pay little attention to coordinating the several people responsible for a timetable or to delivering the result to students.

These observations define the space this work occupies. The contribution sought here is not a new timetabling algorithm — constraint programming already serves that purpose well — but a complete system that wraps a sound constraint solver in a model of the university that reflects how it actually works: its faculty hierarchy, its division of responsibility among officer and faculty heads, and its need to put the finished timetable in front of students simply and reliably. The next chapter sets out the analysis and design of that system.
