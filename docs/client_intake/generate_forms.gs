// Build the API-supported parts of Form A and Form B.
// Paste into script.google.com (new project) and run buildForms().
// LIMITATION: FormApp cannot add file-upload questions, so after running this,
// open Form A and add two File-upload questions (rooms file, courses file) by
// hand — see form_a_faculty_setup.md Sections 4 and 5.

var DEPARTMENTS = [
  'Computer Engineering',
  'Electrical & Electronic Engineering',
  'Civil Engineering',
  'Mechanical Engineering',
];

function buildForms() {
  buildFormA();
  buildFormB();
}

function buildFormA() {
  var form = FormApp.create('Engineering & Technology — Faculty Setup');
  form.setCollectEmail(true);

  form.addSectionHeaderItem().setTitle('Contact & faculty basics');
  form.addTextItem().setTitle('Your full name').setRequired(true);
  form.addTextItem().setTitle('Your email').setRequired(true);
  form.addTextItem().setTitle('Academic year, e.g. 2025/2026').setRequired(true);
  form.addMultipleChoiceItem().setTitle('Which semester is this data for?')
      .setChoiceValues(['Term 1', 'Term 2']).setRequired(true);
  form.addTextItem().setTitle('Sessions per week for a typical course (default 2)')
      .setRequired(true);
  form.addMultipleChoiceItem().setTitle('Session length in hours')
      .setChoiceValues(['1', '2', '3']).setRequired(true);

  form.addPageBreakItem().setTitle('Teaching week & time grid');
  var days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  form.addListItem().setTitle('First teaching day').setChoiceValues(days).setRequired(true);
  form.addListItem().setTitle('Last teaching day').setChoiceValues(days).setRequired(true);
  form.addTextItem().setTitle('Day start time, e.g. 07:30').setRequired(true);
  form.addTextItem().setTitle('Day end time, e.g. 18:00').setRequired(true);
  form.addTextItem().setTitle('Lunch/break window to keep free, e.g. 13:00-14:00')
      .setRequired(true);

  form.addPageBreakItem().setTitle('Departments, levels & classes');
  var levels = ['100', '200', '300', '400', '500'];
  DEPARTMENTS.forEach(function (dept) {
    form.addSectionHeaderItem().setTitle(dept);
    form.addMultipleChoiceItem().setTitle('Is ' + dept + ' part of this faculty?')
        .setChoiceValues(['Yes', 'No']);
    form.addCheckboxItem().setTitle('Which levels does ' + dept + ' run?')
        .setChoiceValues(levels);
    levels.forEach(function (lv) {
      form.addTextItem()
          .setTitle(dept + ' — Level ' + lv + ' class size (leave blank if not run)');
    });
  });
  form.addTextItem().setTitle('Any other department not listed above? (name)');
  form.addTextItem().setTitle('Other department levels and class sizes (e.g. 200:75, 300:60)');

  form.addPageBreakItem().setTitle('Rooms & Courses (uploads)')
      .setHelpText('After this script runs, add two File-upload questions here by '
        + 'hand: the completed rooms_template.xlsx and courses_template.xlsx. '
        + 'FormApp cannot create file-upload questions.');

  Logger.log('Form A: ' + form.getEditUrl());
}

function buildFormB() {
  var form = FormApp.create('Engineering & Technology — Lecturer Registration');
  form.setCollectEmail(true);
  form.addTextItem().setTitle('Full name').setRequired(true);
  form.addTextItem().setTitle('Email').setRequired(true);
  form.addListItem().setTitle('Department')
      .setChoiceValues(DEPARTMENTS.concat(['Other'])).setRequired(true);
  form.addTextItem().setTitle('Courses you teach (codes or names, comma-separated)');
  var grid = form.addCheckboxGridItem();
  grid.setTitle('Tick the half-days you are NOT available to teach')
      .setRows(['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'])
      .setColumns(['Morning', 'Afternoon'])
      .setRequired(true);
  Logger.log('Form B: ' + form.getEditUrl());
}
