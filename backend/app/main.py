from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import (
    auth, universities, faculties, departments, rooms, semesters,
    academic, courses, users, buildings, timetable, export, faculty_setup,
)

app = FastAPI(title="University Timetabling API", version="2.0.0")

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
