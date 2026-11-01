
from sqlalchemy import Column, Integer, String, ForeignKey
from sqlalchemy.orm import relationship

from database import Base


class Apartment(Base):
    __tablename__ = "apartments"

    id = Column(Integer, primary_key=True, index=True)
    flat_number = Column(String(20), unique=True, nullable=False)

    residents = relationship(
        "Resident",
        back_populates="apartment"
    )


class Resident(Base):
    __tablename__ = "residents"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(100), nullable=False)
    email = Column(String(150), unique=True, nullable=False)
    phone = Column(String(20), nullable=False)

    apartment_id = Column(
        Integer,
        ForeignKey("apartments.id"),
        nullable=False
    )

    apartment = relationship(
        "Apartment",
        back_populates="residents"
    )

