# Intake Loading Runbook — Engineering & Technology Pilot

Order matters: each step's data depends on the ones above it. Do them top to
bottom, once all forms are in.

1. **University & faculty.** Ensure the university exists and create the
   Faculty "Engineering & Technology" with sessions-per-week and session-length
   from Form A Section 1 (Q5, Q6).
2. **Semester & time grid.** Create/activate the semester for the term in Form A
   Q4. Enter the teaching days (Q7–Q8) and slice each day from day-start to
   day-end (Q9–Q10) into sessions of the Q6 length, skipping the break window
   (Q11). These become the time slots the solver fills.
3. **Departments, levels, classes.** From Form A Section 3, create each "Yes"
   department, its ticked levels, and one class per level using the class-size
   number as the population.
4. **Rooms.** Open the rooms file from Form A Q12. For each row create the
   building (if new) and the room (capacity, room_type, active) on the rooms
   screen. (No bulk import yet — key them in.)
5. **Courses.** Upload the courses file from Form A Q13 through the course
   bulk-import screen (faculty-head mode). Use Preview first; confirm the shared
   (`|`) rows show the right shared departments, then Import.
6. **Lecturers.** For each Form B response, create a lecturer account
   (create-user, role = lecturer, department from Q3). Then set that lecturer's
   availability as the complement of the ticked half-days (see Form B notes).
7. **Generate.** Start a timetable run for the Engineering & Technology faculty
   and the active semester. Review conflicts; confirm no class or lecturer is
   double-booked and every session fits a room of the required type and size.

## Acceptance check
- All six loading steps complete with no manual database edits.
- A generated run has zero hard conflicts (class clash, lecturer clash,
  room-type mismatch, over-capacity beyond the university overflow threshold).
- The timetable reads back correctly per department and per level.
