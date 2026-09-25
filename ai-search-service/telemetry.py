"""OpenTelemetry tracing. A no-op unless OTEL_EXPORTER_OTLP_ENDPOINT is set, so
local runs and the test suite need no collector."""

import os

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.sqlite3 import SQLite3Instrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def setup(app, span_exporter=None) -> bool:
    """Instrument the app. Returns True if tracing was enabled.

    `span_exporter` lets tests inject an in-memory exporter instead of OTLP.
    """
    if span_exporter is None and not os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return False

    resource = Resource.create(
        {"service.name": os.environ.get("OTEL_SERVICE_NAME", "styleai-search")}
    )
    provider = TracerProvider(resource=resource)
    # OTLPSpanExporter() reads OTEL_EXPORTER_OTLP_ENDPOINT and appends /v1/traces.
    provider.add_span_processor(BatchSpanProcessor(span_exporter or OTLPSpanExporter()))
    trace.set_tracer_provider(provider)

    # Probe and scrape traffic would drown out real requests.
    FastAPIInstrumentor.instrument_app(
        app,
        tracer_provider=provider,
        excluded_urls="health,metrics",
        exclude_spans=["receive", "send"],  # per-message ASGI spans are noise
    )
    RequestsInstrumentor().instrument(tracer_provider=provider)
    SQLite3Instrumentor().instrument(tracer_provider=provider)
    return True
