"""add_email_verification

Revision ID: a1b2c3d4e5f6
Revises: b1e7d3a9c042
Create Date: 2026-08-02 00:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'b1e7d3a9c042'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # New accounts start unverified; existing accounts are grandfathered verified.
    op.add_column('users', sa.Column(
        'is_verified', sa.Boolean(), nullable=False, server_default=sa.true(),
    ))
    op.alter_column('users', 'is_verified', server_default=sa.false())

    op.create_table(
        'verification_tokens',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('token_hash', sa.String(length=64), nullable=False),
        sa.Column('purpose', sa.String(length=20), nullable=False),
        sa.Column('new_email', sa.String(length=200), nullable=True),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
    )
    op.create_index('ix_verification_tokens_token_hash', 'verification_tokens', ['token_hash'])


def downgrade() -> None:
    op.drop_index('ix_verification_tokens_token_hash', table_name='verification_tokens')
    op.drop_table('verification_tokens')
    op.drop_column('users', 'is_verified')
