"""One-shot script to create an Indico admin user (run via indico shell)."""
from indico.modules.auth.models.identities import Identity
from indico.modules.users import User
from indico.modules.users.operations import create_user
from indico.core.db import db

EMAIL = 'admin@example.com'
PASSWORD = 'Admin1234!'

if User.query.filter(User.all_emails == EMAIL, ~User.is_deleted, ~User.is_pending).has_rows():
    print(f'Admin user {EMAIL} already exists, skipping.')
else:
    identity = Identity(provider='indico', identifier='admin', password=PASSWORD)
    user = create_user(EMAIL, {'first_name': 'Admin', 'last_name': 'User', 'affiliation': ''}, identity)
    user.is_admin = True
    db.session.add(user)
    db.session.commit()
    print(f'Created admin user: {EMAIL} / {PASSWORD}')
