
from database import SessionLocal
from models import Apartment, Resident

db = SessionLocal()

try:
    # Create a sample apartment
    apartment = Apartment(flat_number="A-101")
    db.add(apartment)
    db.flush()  # Gets the apartment ID before saving

    # Create a resident linked to that apartment
    resident = Resident(
        full_name="Rahul Sharma",
        email="rahul@example.com",
        phone="9876543210",
        apartment_id=apartment.id
    )

    db.add(resident)
    db.commit()

    print("Sample apartment and resident added!")
    print("Apartment ID:", apartment.id)
    print("Resident:", resident.full_name)
    print("Resident's flat:", resident.apartment.flat_number)

except Exception as error:
    db.rollback()
    print("Error:", error)

finally:
    db.close()
