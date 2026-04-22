from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.academic import Level, Class, ClassGroup
from app.schemas.academic import (
    LevelCreate, LevelOut,
    ClassCreate, ClassUpdate, ClassOut,
    ClassGroupCreate, ClassGroupUpdate, ClassGroupOut,
)
from app.core.permissions import get_current_user, require_university_admin, require_timetable_officer

router = APIRouter(tags=["Academic Structure"])


@router.post("/levels/", response_model=LevelOut, status_code=status.HTTP_201_CREATED)
def create_level(
    payload: LevelCreate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = Level(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/levels/", response_model=list[LevelOut])
def list_levels(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(Level).all()


@router.delete("/levels/{level_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_level(
    level_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_university_admin),
):
    obj = db.get(Level, level_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Level not found")
    db.delete(obj)
    db.commit()


@router.post("/classes/", response_model=ClassOut, status_code=status.HTTP_201_CREATED)
def create_class(
    payload: ClassCreate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = Class(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/classes/", response_model=list[ClassOut])
def list_classes(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(Class).all()


@router.get("/classes/{class_id}", response_model=ClassOut)
def get_class(class_id: int, db: Session = Depends(get_db), _=Depends(get_current_user)):
    obj = db.get(Class, class_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")
    return obj


@router.put("/classes/{class_id}", response_model=ClassOut)
def update_class(
    class_id: int,
    payload: ClassUpdate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = db.get(Class, class_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/classes/{class_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_class(
    class_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = db.get(Class, class_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Class not found")
    db.delete(obj)
    db.commit()


@router.post("/groups/", response_model=ClassGroupOut, status_code=status.HTTP_201_CREATED)
def create_group(
    payload: ClassGroupCreate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = ClassGroup(**payload.model_dump())
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


@router.get("/groups/", response_model=list[ClassGroupOut])
def list_groups(db: Session = Depends(get_db), _=Depends(get_current_user)):
    return db.query(ClassGroup).all()


@router.put("/groups/{group_id}", response_model=ClassGroupOut)
def update_group(
    group_id: int,
    payload: ClassGroupUpdate,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = db.get(ClassGroup, group_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")
    for k, v in payload.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    db.commit()
    db.refresh(obj)
    return obj


@router.delete("/groups/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_group(
    group_id: int,
    db: Session = Depends(get_db),
    _=Depends(require_timetable_officer),
):
    obj = db.get(ClassGroup, group_id)
    if not obj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")
    db.delete(obj)
    db.commit()
