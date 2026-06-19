import logging
import traceback

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from app.routers import (
    auth, universities, faculties, departments, rooms, semesters,
    academic, courses, users, buildings, timetable, export, faculty_setup,
)

app = FastAPI(title="University Timetabling API", version="2.0.0")


class ErrorToJsonMiddleware(BaseHTTPMiddleware):
    """Turn any unhandled error into a JSON 500 response.

    Without this, an unhandled exception propagates past the CORS middleware to
    Starlette's outer error handler, so the 500 response carries no CORS header
    and a browser client reports it only as an opaque network error. Catching it
    here — inside the CORS middleware — lets the CORS headers be attached, so the
    client receives a real, readable 500. (HTTPExceptions are already turned into
    responses further in, so they are not affected.)
    """

    async def dispatch(self, request: Request, call_next):
        try:
            return await call_next(request)
        except Exception:
            logging.error("Unhandled error on %s %s:\n%s",
                          request.method, request.url.path, traceback.format_exc())
            return JSONResponse(status_code=500, content={"detail": "Internal server error"})


# Order matters: the error-catcher is added first so it sits *inside* the CORS
# middleware (added last, therefore outermost), letting CORS headers wrap error
# responses too.
app.add_middleware(ErrorToJsonMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(universities.router)
app.include_router(faculties.router)
app.include_router(departments.router)
app.include_router(buildings.router)
app.include_router(rooms.router)
app.include_router(semesters.router)
app.include_router(academic.router)
app.include_router(courses.router)
app.include_router(users.router)
app.include_router(timetable.router)
app.include_router(faculty_setup.router)
app.include_router(export.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
