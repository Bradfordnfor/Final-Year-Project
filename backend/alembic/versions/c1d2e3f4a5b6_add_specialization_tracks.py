"""add_specialization_tracks

Revision ID: c1d2e3f4a5b6
Revises: a1b2c3d4e5f6
Create Date: 2026-09-05 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'c1d2e3f4a5b6'
down_revision: Union[str, None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('classes', sa.Column('track', sa.String(length=50), nullable=True))
    op.add_column('courses', sa.Column(
        'class_id', sa.Integer(),
        sa.ForeignKey('classes.id'), nullable=True,
    ))


def downgrade() -> None:
    op.drop_column('courses', 'class_id')
    op.drop_column('classes', 'track')
