"""One-off loader: create lecturer accounts for FET from a name list.

Email = <firstname>@<DEPT_CODE>.com  (firstname = first name token after the
title, lowercased). Passwords are generated and written out with the rest of
the credentials. Re-runnable: a lecturer whose email already exists is skipped.

Run from the backend/ directory:
    ./venv/Scripts/python.exe scripts/load_lecturers.py
"""
import csv
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import SessionLocal
from app.models.university import University, Faculty, Department
from app.models.user import User, Lecturer
from app.core.security import get_password_hash

# name lists keyed by department code
ROSTER = {
    "CE": [
        "Dr Tsaue Aline", "Dr Njouela Ines", "Dr Sop Deffo", "Dr. Kamjou Marie",
        "Dr. Kemeni Valery", "Dr. Dor", "Dr. Azeufack", "Eng Patrick",
        "Dr Peter Leke", "Mr. Foncha Glenn", "Dr Achille",
    ],
    "EE": [
        "Dr Winkar Basil", "Dr SImo", "Dr Tabetah Marshall", "Dr Tene",
        "Dr Fenji", "Dr Fotso Raul", "Prof Ngwashi Divine", "Prof Fopah Amad",
        "Dr Ayeketang", "Dr Musong Luise", "Dr Serge", "Prof Pierre",
        "Dr Sitamze", "Dr Nouajep Serge", "Dr Djob",
    ],
    "CIV": [
        "Dr Akana Leonard", "Dr Charles Abi", "Dr Ngandeu Blaise",
        "Mr Njouny Emmanuel", "Mr Oben Rudolf", "Dr Narcisse Alain",
        "Dr Mwebi clautaire", "Dr Ines Leana", "Dr Njike Mannette",
        "Dr Tata Sunjo", "Dr Lontsi Marios", "Dr Sitamze Bertrand",
    ],
    "ME": [
        "Dr Wamba", "Dr Fopah Lele", "Dr Ehinak Albert", "Dr Temgoua",
        "Dr Awah Terence", "Dr Aquingeh", "Dr Ndeh Louis", "Prof Mbelle",
    ],
}

TITLES = {"dr", "dr.", "prof", "prof.", "mr", "mr.", "mrs", "mrs.",
          "ms", "ms.", "eng", "eng.", "engr", "engr.", "miss", "prof."}


def first_name(full_name: str) -> str:
    tokens = full_name.split()
    for tok in tokens:
        if tok.lower().strip(".") + "." in TITLES or tok.lower() in TITLES:
            continue
        return tok
    return tokens[-1]  # fallback: should not happen


def main():
    db = SessionLocal()
    uni = db.query(University).filter(University.slug == "UB").first()
    fac = db.query(Faculty).filter(
        Faculty.university_id == uni.id, Faculty.code == "FET").first()
    dept_by_code = {
        d.code: d for d in
        db.query(Department).filter(Department.faculty_id == fac.id).all()
    }

    rows = []
    created, skipped = 0, 0
    for code, names in ROSTER.items():
        dept = dept_by_code[code]
        for full_name in names:
            full_name = full_name.strip()
            email = f"{first_name(full_name).lower()}@{code}.com"
            existing = db.query(User).filter(User.email == email).first()
            if existing:
                skipped += 1
                rows.append([full_name, email, fac.name, dept.name, "(exists)"])
                continue
            password = secrets.token_urlsafe(8)
            user = User(
                email=email, full_name=full_name,
                hashed_password=get_password_hash(password),
                role="lecturer", is_active=True,
                university_id=uni.id, faculty_id=fac.id, department_id=dept.id,
            )
            db.add(user)
            db.flush()
            db.add(Lecturer(user_id=user.id, department_id=dept.id))
            created += 1
            rows.append([full_name, email, fac.name, dept.name, password])

    db.commit()
    db.close()

    out = Path(__file__).resolve().parents[2] / "lecturer_credentials.csv"
    with out.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["name", "email", "faculty", "department", "password"])
        writer.writerows(rows)

    print(f"created={created} skipped={skipped} total={len(rows)}")
    print(f"CSV written to: {out}")


if __name__ == "__main__":
    main()
