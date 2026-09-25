from unittest.mock import MagicMock, patch

import pytest
import test_main  # sets DB_PATH/IMAGE_DIR and imports main before anything else does
from fastapi import FastAPI
from fastapi.testclient import TestClient
from opentelemetry import trace
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

import telemetry

main = test_main.main


def test_setup_is_noop_without_endpoint(monkeypatch):
    monkeypatch.delenv("OTEL_EXPORTER_OTLP_ENDPOINT", raising=False)
    assert telemetry.setup(FastAPI()) is False


@pytest.fixture(scope="module")
def exporter():
    exp = InMemorySpanExporter()
    dummy = FastAPI()

    @dummy.get("/ping")
    def ping():
        return {"ok": True}

    @dummy.get("/health")
    def health():
        return {"status": "ok"}

    assert telemetry.setup(dummy, span_exporter=exp) is True
    yield exp, TestClient(dummy)


def _flush_and_names(exp):
    trace.get_tracer_provider().force_flush()
    return [s.name for s in exp.get_finished_spans()]


def test_requests_are_traced_but_probes_are_not(exporter):
    exp, client = exporter
    exp.clear()
    client.get("/ping")
    client.get("/health")
    names = _flush_and_names(exp)
    assert any("/ping" in n for n in names)
    assert not any("/health" in n for n in names)


def test_search_emits_llm_and_db_spans(exporter):
    exp, _ = exporter
    exp.clear()
    mock_response = MagicMock()
    mock_response.raise_for_status.return_value = None
    mock_response.json.return_value = {
        "message": {"tool_calls": [{"function": {"arguments": {"category": "pants", "color": "red"}}}]}
    }
    with patch("main.requests.post", return_value=mock_response):
        main.search(main.SearchRequest(query="red pants"))
    trace.get_tracer_provider().force_flush()
    spans = {s.name: s for s in exp.get_finished_spans()}

    llm = spans["llm.parse_query"]
    assert llm.attributes["llm.model"] == main.OLLAMA_MODEL
    assert llm.attributes["search.filters"] == "category,color"
    assert llm.attributes["llm.tool_called"] is True
    assert spans["db.run_query"].attributes["search.result_count"] == 1
