# CHAPTER 5: CONCLUSION AND FURTHER WORKS

This final chapter draws the work to a close. It summarises what the project set out to do and what it achieved, states the contribution it makes, offers recommendations to those who would deploy or extend it, records the difficulties met along the way, and sets out the further work that would carry the system from a working prototype to a product a university could rely on day to day.

## 5.1 Summary of Findings

This work set out to replace a manual, error-prone way of building university timetables with an automated system that generates a valid timetable, coordinates the staff responsible for it, and delivers the result to students. Each of those aims was met.

A single structured database was built to hold the academic data of a university in the shape it actually takes — faculties, departments, levels, classes, courses, lecturers, buildings, rooms, and time periods — and this database drove every later stage. University timetabling was formulated for a constraint solver and implemented as an automatic generator that respects the hard scheduling rules by construction; exercised on the real first-semester data of the Faculty of Engineering and Technology, it produced an optimal, entirely clash-free timetable of 185 sessions in about thirty-two seconds. A role-based workflow was built around the generator so that a draft is reviewed and approved by the accountable faculty heads before it is published, replacing the informal circulation of the manual process with a recorded chain of approval. The exceptions that scheduling inevitably raises — laboratory classes too large to split within the week, and the occasional need to move a session by hand — are handled through conflict resolution and clash-checked manual edits. And the finished timetable is published to a view that a student reaches without an account and narrows to their own class.

The evaluation of Chapter 4 showed that, against the manual process it replaces, the system offers correctness by construction, generation in seconds rather than days, and a coordination mechanism the manual process simply lacks.

## 5.2 Contribution to Engineering and Technology

The contribution of this work is less the invention of a new scheduling algorithm than the engineering of a complete, usable system around a proven one. Three aspects are worth naming.

First, it demonstrates that constraint programming — specifically Google OR-Tools' CP-SAT solver — is well able to handle timetabling at the scale of a real faculty on ordinary hardware, returning a provably optimal result for the case-study instance in well under a minute. This is a concrete data point for any Cameroonian institution weighing whether automated timetabling is practical for it.

Second, and more distinctively, it joins that solver to the two things the existing tools surveyed in Chapter 2 leave out: a multi-role review-and-approval workflow that establishes accountability for a timetable before it takes effect, and a student-facing distribution channel that needs no account. The combination — generation, coordination, and distribution in one system — is the part of the work that addresses the institutional problem rather than only the algorithmic one.

Third, the data model and the system are shaped to the faculty–department–level structure of a Cameroonian university, with the realities that structure carries — shared courses across classes, university-wide requirements every student must pass, a chronic shortage of large halls handled by a tunable overflow allowance, and practical courses held off-site. This makes the system directly applicable in its intended setting rather than an approximation of it.

## 5.3 Recommendations

For the University of Buea and institutions like it, the recommendation is that automated timetabling of this kind is worth adopting, and that the adoption is mainly a matter of data discipline rather than technology: the quality of a generated timetable depends entirely on the academic data being complete and current, so the practices that keep course lists, lecturer assignments, and room records up to date are what will determine the system's value in use. The overflow allowance should be set deliberately by each university as a statement of how much crowding it is prepared to tolerate in exchange for fewer separate lectures.

For anyone deploying the system beyond a demonstration, the strongest recommendation is to add verified, email-backed account provisioning before real users are onboarded, as Section 5.5 describes; until then, accounts rest on admin-entered addresses that are not proven to belong to the people they name.

For future developers, the recommendation is to preserve the separation that this work was careful to maintain — the scheduling core kept independent of the database and the web, joined to the rest of the system only by plain data structures — because it is what allowed the engine to be tested and improved in isolation, and it is what would allow the solver to be extended, or even replaced, without disturbing the system around it.

## 5.4 Difficulties Encountered

Several difficulties shaped the work and are worth recording. The first was expressing the messiness of real timetabling in the clean language of constraints: deciding, for instance, that an over-full room should be permitted and flagged rather than forbidden, because forbidding it outright would often leave the chronically hall-short faculty with no solution at all. A related difficulty appeared only once the system met real data — the solver, asked merely to satisfy the constraints, would assign rooms with no regard to fit, placing a small class in a large hall while a larger class overflowed a smaller room. This was resolved by giving the solver an objective to minimise wasted capacity, which turned a merely valid timetable into a sensible one and, on the case-study data, cut the over-capacity placements from forty-five to the nine the halls genuinely force.

A second class of difficulty lay in the parts of the domain that a first design overlooks: university-wide courses that every class must take, which had to be packed into shared sessions rather than repeated class by class; practical courses that need no room at all; and the realisation that generating a draft more than once must replace the previous result rather than stack a second timetable on top of it, a subtlety whose absence first showed up as duplicated and clashing sessions. A third was the discipline of testing a system whose development database and test database differ — the latter not enforcing the referential rules the former does — which meant that certain ordering errors passed the tests yet would have failed against real data, and had to be guarded against deliberately.

None of these proved insurmountable, but each is a reminder that the distance between a correct algorithm and a dependable system is made up of exactly such details.

## 5.5 Further Works

The system is complete for the purpose of this dissertation, but several enhancements would be needed before it could be marketed and relied upon, and others would extend its usefulness.

The most important is **verified, email-backed account provisioning**. At present an account is created by an administrator against an email address that is never proven to exist or to belong to the person named, and an address cannot be changed after creation. The natural solution, given that accounts are provisioned by an administrator for someone else, is an invitation flow: the administrator creates the account with only a name, email, and role; the system emails a single-use link; and clicking it both verifies the address and lets the person set their own password. This one change would prove that accounts belong to real, intended people, remove the present hand-off of a temporary password, and supply the email-change path that is currently missing. It requires an outbound email capability the system does not yet have — the in-app notifications are database records only — and so would also let notifications graduate from in-app messages to real email.

A second enhancement is the modelling of **soft preferences** alongside the hard constraints: a lecturer's preferred rather than merely possible times, or a faculty's wish to group a class's lectures into the morning or to avoid isolated single periods. The constraint model already carries an objective, so such preferences could be added as further terms to be optimised, producing timetables that are not only valid but pleasant to teach and to attend.

A third concerns **scale**. The case-study instance, a single faculty, was solved to proven optimality within the time bound; a run spanning several faculties at once may reach only a feasible solution before the bound is reached. Investigating how the solver behaves on university-wide instances — and, if needed, decomposing a large problem into cooperating sub-problems — would establish the system's limits and extend them.

Beyond these, the system invites the familiar extensions of a scheduling product: a dedicated examination-timetabling mode, export of a personal timetable to a phone calendar, and a native mobile application to sit alongside the web client the present work already supports. Each builds naturally on the foundation this project has laid.

## 5.6 Concluding Remarks

The construction of a university timetable is a problem that is easy to state and hard to do well by hand, and the cost of doing it badly is borne all semester by everyone the timetable governs. This work has shown that the problem yields to automation: that a constraint solver can produce a correct timetable for a real faculty in seconds, that the people accountable for it can be brought into a recorded workflow around it, and that the result can be put into a student's hands through nothing more than a link. What remains is the work of turning a sound prototype into a deployed product, and the path to that, set out above, is clear.
