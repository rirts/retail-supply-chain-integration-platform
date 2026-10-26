import json
from contextlib import contextmanager
from unittest.mock import MagicMock
import pytest
from scripts import consume_inventory_events_to_raw as module

@pytest.mark.parametrize("failure", [False, True])
def test_offset_follows_successful_database_commit(monkeypatch, failure):
    events = []
    conn = MagicMock()
    conn.__enter__.return_value = conn
    @contextmanager
    def transaction():
        yield
        events.append("database_commit")
    conn.transaction.side_effect = transaction
    consumer = MagicMock()
    message = MagicMock()
    message.error.return_value = None
    message.value.return_value = json.dumps({"event_id": "test"}).encode()
    consumer.poll.side_effect = [message, None]
    consumer.commit.side_effect = lambda **kw: events.append("offset_commit")
    factory = MagicMock(return_value=consumer)
    monkeypatch.setattr(module, "Consumer", factory)
    monkeypatch.setattr(module, "get_connection", lambda: conn)
    monkeypatch.setattr(module, "create_event_batch", lambda *a, **kw: "batch")
    def insert(**kw):
        if failure:raise RuntimeError("database write failed")
        events.append("insert")
        return True
    monkeypatch.setattr(module, "insert_event_raw", insert)
    if failure:
        with pytest.raises(RuntimeError):module.consume_events(1,1)
        assert "offset_commit" not in events
    else:
        module.consume_events(1,1)
        i = events.index("offset_commit")
        assert events[i-1] == "database_commit"
    assert factory.call_args.args[0]["group.id"] == "inventory-raw-loader"
