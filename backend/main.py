
from fastapi import FastAPI, Depends
from sqlalchemy.orm import Session, joinedload

from database import SessionLocal
from models import Apartment

from pydantic import BaseModel
from fastapi import HTTPException

app = FastAPI(title="SocietyOS API")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@app.get("/health")
def health():
    return {"status": "ok", "service": "SocietyOS"}


@app.get("/apartments")
def get_apartments(db: Session = Depends(get_db)):
    apartments = (
        db.query(Apartment)
        .options(joinedload(Apartment.residents))
        .all()
    )

    return [
        {
            "id": apartment.id,
            "flat_number": apartment.flat_number,
            "residents": [
                {
                    "id": resident.id,
                    "full_name": resident.full_name,
                    "email": resident.email,
                    "phone": resident.phone,
                }
                for resident in apartment.residents
            ],
        }
        for apartment in apartments
    ]


class ApartmentCreate(BaseModel):
    flat_number: str


@app.post("/apartments")
def create_apartment(
    apartment_data: ApartmentCreate,
    db: Session = Depends(get_db)
):
    existing = db.query(Apartment).filter(
        Apartment.flat_number == apartment_data.flat_number
    ).first()

    if existing:
        raise HTTPException(
            status_code=400,
            detail="Apartment already exists"
        )

    apartment = Apartment(
        flat_number=apartment_data.flat_number
    )

    db.add(apartment)
    db.commit()
    db.refresh(apartment)

    return {
        "message": "Apartment created successfully",
        "id": apartment.id,
        "flat_number": apartment.flat_number
    }
