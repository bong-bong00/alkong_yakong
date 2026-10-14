from unittest.mock import MagicMock
import pytest
from scripts.check_neon_readiness import inspect_connection, main


def test_readiness_checks_are_read_only_and_use_verified_tls(monkeypatch):
    import psycopg
    connection = MagicMock()
    response = MagicMock()
    response.fetchone.side_effect = [('18.6',), ('on',)]
    response.fetchall.return_value = [('alkong_main', 25)]
    connection.execute.return_value = response
    connect = MagicMock()
    connect.return_value.__enter__.return_value = connection
    monkeypatch.setattr(psycopg, 'connect', connect)
    result = inspect_connection('postgresql://u:private@ep-test.neon.tech/neondb?sslmode=disable')
    assert connection.execute.call_args_list[0].args == ('SET TRANSACTION READ ONLY',)
    assert connect.call_args.kwargs['sslmode'] == 'verify-full'
    assert result['transaction_read_only'] and result['schema_table_counts']['alkong_main'] == 25
    assert not result['migration_completed'] and not result['changes_made']
    assert 'private' not in str(result)


def test_neon_check_rejects_unexpected_destination_before_connection(monkeypatch):
    import psycopg
    connect = MagicMock()
    monkeypatch.setattr(psycopg, 'connect', connect)
    with pytest.raises(ValueError):
        inspect_connection('postgresql://u:private@example.invalid/db')
    connect.assert_not_called()


def test_cli_never_prints_credentials_or_remote_error_text(monkeypatch, capsys):
    import scripts.check_neon_readiness as checker
    def failed(_):
        raise ValueError('private-password and patient information')
    monkeypatch.setattr(checker, 'inspect_connection', failed)
    with pytest.raises(SystemExit):
        main()
    output = capsys.readouterr()
    assert 'ValueError' in output.err
    assert 'private-password' not in output.err and 'patient information' not in output.err
