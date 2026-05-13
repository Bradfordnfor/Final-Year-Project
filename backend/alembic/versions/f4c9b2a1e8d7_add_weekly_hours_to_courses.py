"""add_weekly_hours_to_courses

Revision ID: f4c9b2a1e8d7
Revises: 3a7f82c9d1e4
Create Date: 2026-04-24 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'f4c9b2a1e8d7'
down_revision: Union[str, None] = '3a7f82c9d1e4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('courses', sa.Column(
        'weekly_hours', sa.Integer(), nullable=False, server_default='2',
    ))


def downgrade() -> None:
    op.drop_column('courses', 'weekly_hours')
