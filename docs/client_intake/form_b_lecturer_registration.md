# Form B — Lecturer Registration (Engineering & Technology)

Who fills it: each lecturer, once for themselves.
Form settings: "Collect email addresses" ON, "Limit to 1 response" OFF (many
lecturers). Title: "Engineering & Technology — Lecturer Registration".

## Questions
1. Full name — Short answer (required) → becomes the lecturer's account name
2. Email — Short answer (required) → the activation invite is sent here
3. Department — Dropdown (required): Computer Engineering · Electrical &
   Electronic Engineering · Civil Engineering · Mechanical Engineering · Other
4. Courses you teach (codes or names, comma-separated) — Short answer (optional)
5. Availability — Checkbox grid (required):
   - Prompt: "Tick the half-days you are NOT available to teach."
   - Rows: Monday, Tuesday, Wednesday, Thursday, Friday (add Saturday only if the
     faculty teaches Saturdays, per Form A Section 2).
   - Columns: Morning · Afternoon
   - A ticked cell = unavailable. Anything left un-ticked is treated as available.

## Notes for the operator
- Create one lecturer account per response (they are NOT bulk imported): use the
  create-user screen with role = lecturer and the department from Q3; this emails
  the activation link.
- Record availability as the COMPLEMENT of the ticked cells: the app stores the
  slots a lecturer IS available for, so translate "Mon Morning ticked" into
  "exclude all Monday-morning time slots" when setting their availability.
- If a lecturer ticks nothing, they are available for the whole teaching week.
