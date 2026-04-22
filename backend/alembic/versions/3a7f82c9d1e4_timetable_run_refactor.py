"""timetable_run_refactor

Revision ID: 3a7f82c9d1e4
Revises: 1d55b5e43cf1
Create Date: 2026-04-22 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '3a7f82c9d1e4'
down_revision: Union[str, None] = '1d55b5e43cf1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Drop old timetable-related tables (order respects FK deps)
    op.drop_table('timetable_entry_classes')
    op.drop_table('timetable_entries')
    op.drop_table('timetable_conflicts')
    op.drop_table('generation_jobs')
    op.drop_table('timetables')

    # Create timetable_runs
    op.create_table(
        'timetable_runs',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('name', sa.String(200), nullable=False),
        sa.Column('status', sa.String(20), nullable=False, server_default='draft'),
        sa.Column('semester_id', sa.Integer(), sa.ForeignKey('semesters.id'), nullable=False),
        sa.Column('created_by', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('generated_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )

    # Many-to-many: run ↔ faculty
    op.create_table(
        'timetable_run_faculties',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('run_id', sa.Integer(), sa.ForeignKey('timetable_runs.id'), nullable=False),
        sa.Column('faculty_id', sa.Integer(), sa.ForeignKey('faculties.id'), nullable=False),
    )

    # Many-to-many: run ↔ building
    op.create_table(
        'timetable_run_buildings',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('run_id', sa.Integer(), sa.ForeignKey('timetable_runs.id'), nullable=False),
        sa.Column('building_id', sa.Integer(), sa.ForeignKey('buildings.id'), nullable=False),
    )

    # timetable_entries (run_id replaces timetable_id)
    op.create_table(
        'timetable_entries',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('run_id', sa.Integer(), sa.ForeignKey('timetable_runs.id'), nullable=False),
        sa.Column('course_id', sa.Integer(), sa.ForeignKey('courses.id'), nullable=False),
        sa.Column('lecturer_id', sa.Integer(), sa.ForeignKey('lecturers.id'), nullable=False),
        sa.Column('room_id', sa.Integer(), sa.ForeignKey('rooms.id'), nullable=False),
        sa.Column('time_slot_id', sa.Integer(), sa.ForeignKey('time_slots.id'), nullable=False),
        sa.Column('group_id', sa.Integer(), sa.ForeignKey('class_groups.id'), nullable=True),
        sa.Column('week_pattern', sa.String(20), nullable=False, server_default='every_week'),
        sa.Column('rotation_sequence', sa.Text(), nullable=True),
        sa.Column('is_overcapacity', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('is_merged', sa.Boolean(), nullable=False, server_default='0'),
    )

    op.create_table(
        'timetable_entry_classes',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('entry_id', sa.Integer(), sa.ForeignKey('timetable_entries.id'), nullable=False),
        sa.Column('class_id', sa.Integer(), sa.ForeignKey('classes.id'), nullable=False),
    )

    op.create_table(
        'timetable_conflicts',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('run_id', sa.Integer(), sa.ForeignKey('timetable_runs.id'), nullable=False),
        sa.Column('conflict_type', sa.String(50), nullable=False),
        sa.Column('course_id', sa.Integer(), sa.ForeignKey('courses.id'), nullable=True),
        sa.Column('class_id', sa.Integer(), sa.ForeignKey('classes.id'), nullable=True),
        sa.Column('details', sa.Text(), nullable=False, server_default='{}'),
        sa.Column('resolved', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('resolution', sa.String(20), nullable=True),
    )

    op.create_table(
        'generation_jobs',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('run_id', sa.Integer(), sa.ForeignKey('timetable_runs.id'), nullable=False),
        sa.Column('status', sa.String(20), nullable=False, server_default='pending'),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('started_at', sa.DateTime(), nullable=True),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
    )

    # Add level_id to courses
    op.add_column('courses', sa.Column('level_id', sa.Integer(), sa.ForeignKey('levels.id'), nullable=True))


def downgrade() -> None:
    op.drop_column('courses', 'level_id')
    op.drop_table('generation_jobs')
    op.drop_table('timetable_conflicts')
    op.drop_table('timetable_entry_classes')
    op.drop_table('timetable_entries')
    op.drop_table('timetable_run_buildings')
    op.drop_table('timetable_run_faculties')
    op.drop_table('timetable_runs')

    op.create_table(
        'timetables',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('status', sa.String(20), nullable=False, server_default='draft'),
        sa.Column('semester_id', sa.Integer(), sa.ForeignKey('semesters.id'), nullable=False),
        sa.Column('department_id', sa.Integer(), sa.ForeignKey('departments.id'), nullable=False),
        sa.Column('generated_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_table(
        'timetable_entries',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('timetable_id', sa.Integer(), sa.ForeignKey('timetables.id'), nullable=False),
        sa.Column('course_id', sa.Integer(), sa.ForeignKey('courses.id'), nullable=False),
        sa.Column('lecturer_id', sa.Integer(), sa.ForeignKey('lecturers.id'), nullable=False),
        sa.Column('room_id', sa.Integer(), sa.ForeignKey('rooms.id'), nullable=False),
        sa.Column('time_slot_id', sa.Integer(), sa.ForeignKey('time_slots.id'), nullable=False),
        sa.Column('group_id', sa.Integer(), sa.ForeignKey('class_groups.id'), nullable=True),
        sa.Column('week_pattern', sa.String(20), nullable=False, server_default='every_week'),
        sa.Column('rotation_sequence', sa.Text(), nullable=True),
        sa.Column('is_overcapacity', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('is_merged', sa.Boolean(), nullable=False, server_default='0'),
    )
    op.create_table(
        'timetable_entry_classes',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('entry_id', sa.Integer(), sa.ForeignKey('timetable_entries.id'), nullable=False),
        sa.Column('class_id', sa.Integer(), sa.ForeignKey('classes.id'), nullable=False),
    )
    op.create_table(
        'timetable_conflicts',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('timetable_id', sa.Integer(), sa.ForeignKey('timetables.id'), nullable=False),
        sa.Column('conflict_type', sa.String(50), nullable=False),
        sa.Column('course_id', sa.Integer(), sa.ForeignKey('courses.id'), nullable=True),
        sa.Column('class_id', sa.Integer(), sa.ForeignKey('classes.id'), nullable=True),
        sa.Column('details', sa.Text(), nullable=False, server_default='{}'),
        sa.Column('resolved', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('resolution', sa.String(20), nullable=True),
    )
    op.create_table(
        'generation_jobs',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('timetable_id', sa.Integer(), sa.ForeignKey('timetables.id'), nullable=False),
        sa.Column('status', sa.String(20), nullable=False, server_default='pending'),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('started_at', sa.DateTime(), nullable=True),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
    )
