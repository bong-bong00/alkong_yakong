import sqlite3
import unittest
from unittest.mock import patch
from app.services.pharmacist.cache_context import health_cache_context


class CacheContextTest(unittest.TestCase):
    def context(self, smoking='no', name='name'):
        conn = sqlite3.connect(':memory:')
        conn.row_factory = sqlite3.Row
        conn.execute('CREATE TABLE users (id TEXT, smoking TEXT, name TEXT)')
        conn.execute('INSERT INTO users VALUES (?, ?, ?)', ('user', smoking, name))
        with patch('app.services.pharmacist.cache_context.get_connection', return_value=conn):
            return health_cache_context('user')

    def test_token_changes_for_health_not_name_and_contains_no_health_fields(self):
        first = self.context()
        self.assertTrue(first['verified'])
        self.assertEqual(first, self.context(name='another name'))
        self.assertNotEqual(first, self.context(smoking='yes'))
        self.assertEqual(set(first), {'verified', 'fingerprint'})

    def test_unknown_database_is_not_verified(self):
        with patch('app.services.pharmacist.cache_context.get_connection',
                   side_effect=sqlite3.OperationalError()):
            self.assertEqual(health_cache_context('user'), {'verified': False})
