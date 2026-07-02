# Preliminary Pages

> Source content for the preliminary pages. `build_report.py` lays out the cover
> and title pages and inserts the auto-generated Table of Contents, List of
> Tables, and List of Figures; the prose below (certification, dedication,
> acknowledgement, abstract, abbreviations) is taken verbatim.

---

## Cover / Title page (identity)

- **Institution:** Republic of Cameroon, University of Buea
- **Faculty:** Faculty of Engineering and Technology
- **Department:** Department of Computer Engineering
- **Title:** Design and Implementation of an Automated Timetable Generation and Management System for Universities
- **Submission line:** A dissertation submitted to the Department of Computer Engineering, Faculty of Engineering and Technology, University of Buea, in partial fulfilment of the requirements for the award of a Bachelor of Engineering (B.Eng.) degree in Computer Engineering.
- **Author:** NFOR RINGDAH BRADFORD
- **Matriculation number:** FE22A257
- **Option:** Software Engineering
- **Supervisor:** Dr. Nde Nguti
- **Academic Year:** 2025/2026

---

## Certification

This is to certify that this dissertation, entitled **"Design and Implementation of an Automated Timetable Generation and Management System for Universities"**, is the original work of **NFOR RINGDAH BRADFORD**, registration number **FE22A257**, carried out in the Department of Computer Engineering, Faculty of Engineering and Technology, University of Buea, in partial fulfilment of the requirements for the award of a Bachelor of Engineering (B.Eng.) degree in Computer Engineering. The work reported here was conducted by the candidate under supervision and has not been presented elsewhere for the award of any degree.

<br>

_______________________________  
**NFOR RINGDAH BRADFORD** (Candidate)   Date: ____________

<br>

_______________________________  
**Dr. Nde Nguti** (Supervisor)   Date: ____________

<br>

_______________________________  
**Head of Department**, Computer Engineering   Date: ____________

---

## Dedication

> *Optional, up to 3 honourees. Personalise before submission.*

To my family, for their constant support and encouragement throughout my studies.

---

## Acknowledgement

I am grateful to God for the strength and perseverance to see this work through.

I owe particular thanks to my supervisor, **Dr. Nde Nguti**, whose guidance, patience, and careful feedback shaped this project at every stage. I thank the lecturers and staff of the Department of Computer Engineering, Faculty of Engineering and Technology, University of Buea, for the foundation on which this work is built, and for the practical insight into the timetabling process that motivated it.

Finally, I thank my family and friends for their unfailing support, and my classmates for the discussions and encouragement that accompanied this work.

> *Personalise: add specific names you wish to acknowledge before submission.*

---

## Abstract

At the University of Buea, as at many institutions, academic timetables are still built and managed by hand. A few staff reconcile the competing demands of courses, lecturers, classes and rooms without any tool to enforce the scheduling rules or to warn them when a rule is broken. The result is slow to produce, prone to clashes that surface only once teaching has begun, not formally coordinated among the people responsible for it, and hard to distribute to the students who must follow it. This work designs and implements an automated system that answers these weaknesses across the whole life of a timetable. It first captures the academic structure of a university, from faculties and departments down to levels, classes, courses, lecturers, buildings, rooms and time periods, in a single relational model that scheduling can build on. University timetabling is then formulated as a constraint optimisation problem and solved with Google OR-Tools' CP-SAT solver. The solver satisfies the hard constraints by construction: no lecturer, class or room is double-booked, every session is given a room of the type it needs, and lecturer unavailability is respected. On top of these rules, an objective minimises wasted seats, so that the large and shared sessions are placed in the larger halls.

Around the generator sits a role-based workflow. A timetable officer generates and submits a draft, each faculty head approves the part that concerns their faculty, and only an approved timetable is published. Exceptions such as oversubscribed laboratories or a last-minute move are handled through conflict resolution and clash-checked manual edits, and students reach the published timetable through a public view that needs no account and narrows to a single class. The system was built as a FastAPI service with a Flutter client and evaluated on the real first-semester data of the Faculty of Engineering and Technology. There it produced a provably optimal, entirely clash-free timetable of 185 sessions across 89 courses, 13 classes and 45 lecturers in about thirty-two seconds, where the manual process is measured in days. The evaluation shows that the system meets each of its objectives, and that against the manual process it replaces it offers correctness by construction, generation in seconds, and a recorded chain of accountability.

**Keywords:** university timetabling, constraint programming, CP-SAT, automated scheduling, approval workflow, FastAPI, Flutter.

---

## List of Abbreviations

| Abbreviation | Meaning |
|---|---|
| API | Application Programming Interface |
| B.Eng. | Bachelor of Engineering |
| CP-SAT | Constraint Programming - Satisfiability (Google OR-Tools solver) |
| CSV | Comma-Separated Values |
| ER | Entity-Relationship |
| FET | Faculty of Engineering and Technology |
| HOD | Head of Department |
| JWT | JSON Web Token |
| NP | Nondeterministic Polynomial (time) |
| OR-Tools | Operations Research Tools (Google) |
| ORM | Object-Relational Mapping |
| PDF | Portable Document Format |
| RBAC | Role-Based Access Control |
| REST | Representational State Transfer |
| SQL | Structured Query Language |
| UB | University of Buea |
| UI | User Interface |
| UML | Unified Modeling Language |
