
from database import Base, engine
import models  # Registers Apartment and Resident models

Base.metadata.create_all(bind=engine)

print("SocietyOS tables created successfully!")
