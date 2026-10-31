from fastapi import FastAPI

app = FastAPI(title="SocietyOS API")


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "SocietyOS"
    }