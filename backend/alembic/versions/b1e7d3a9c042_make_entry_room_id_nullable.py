"""make timetable_entries.room_id nullable for outdoor sessions

Revision ID: b1e7d3a9c042
Revises: f4c9b2a1e8d7
Create Date: 2026-06-20 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'b1e7d3a9c042'
down_revision: Union[str, None] = 'f4c9b2a1e8d7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # SQLite cannot ALTER a column in place, so use batch mode.
    with op.batch_alter_table('timetable_entries') as batch_op:
        batch_op.alter_column('room_id', existing_type=sa.Integer(), nullable=True)


def downgrade() -> None:
    with op.batch_alter_table('timetable_entries') as batch_op:
        batch_op.alter_column('room_id', existing_type=sa.Integer(), nullable=False)
