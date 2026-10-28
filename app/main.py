import logging
import time
import uuid
from collections.abc import Iterator
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db import Base, Item, make_engine
from app.logging_config import configure_logging

logger = logging.getLogger("apex")


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    status: Literal["open", "in_progress", "closed"] = "open"


class ItemOut(ItemIn):
    model_config = ConfigDict(from_attributes=True)
    id: int


def create_app(database_url: str | None = None) -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        Base.metadata.create_all(app.state.engine)
        logger.info("startup complete", extra={"version": settings.app_version})
        yield
        app.state.engine.dispose()

    app = FastAPI(title="Apex Operations API", version=settings.app_version, lifespan=lifespan)
    app.state.engine = make_engine(database_url or settings.database_url)

    def get_session(request: Request) -> Iterator[Session]:
        with Session(request.app.state.engine) as session:
            yield session

    @app.middleware("http")
    async def log_requests(request: Request, call_next):
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        start = time.perf_counter()
        response = await call_next(request)
        logger.info(
            "request",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": round((time.perf_counter() - start) * 1000, 2),
            },
        )
        response.headers["x-request-id"] = request_id
        return response

    @app.exception_handler(SQLAlchemyError)
    async def db_error(request: Request, exc: SQLAlchemyError):
        logger.error("database error", extra={"path": request.url.path, "error": str(exc)})
        return JSONResponse(status_code=503, content={"detail": "database unavailable"})

    @app.get("/health")
    def health():
        """Liveness: the process is up. Never touches dependencies."""
        return {"status": "ok"}

    @app.get("/ready")
    def ready(request: Request):
        """Readiness: we can actually serve traffic (database reachable)."""
        try:
            with request.app.state.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
        except SQLAlchemyError as exc:
            logger.warning("readiness check failed", extra={"error": str(exc)})
            return JSONResponse(status_code=503, content={"status": "not ready", "db": "down"})
        return {"status": "ready", "db": "up"}

    @app.get("/version")
    def version():
        return {"version": settings.app_version}

    @app.get("/items", response_model=list[ItemOut])
    def list_items(session: Session = Depends(get_session)):
        return session.scalars(select(Item).order_by(Item.id)).all()

    @app.post("/items", response_model=ItemOut, status_code=201)
    def create_item(payload: ItemIn, session: Session = Depends(get_session)):
        item = Item(**payload.model_dump())
        session.add(item)
        session.commit()
        session.refresh(item)
        logger.info("item created", extra={"item_id": item.id})
        return item

    @app.get("/items/{item_id}", response_model=ItemOut)
    def get_item(item_id: int, session: Session = Depends(get_session)):
        item = session.get(Item, item_id)
        if item is None:
            raise HTTPException(status_code=404, detail="item not found")
        return item

    Instrumentator().instrument(app).expose(app, include_in_schema=False)
    return app


app = create_app()
