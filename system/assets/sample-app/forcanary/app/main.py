import socket

from fastapi import FastAPI

app = FastAPI()


def _get_container_ip() -> str | None:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
    except OSError:
        try:
            return socket.gethostbyname(socket.gethostname())
        except OSError:
            return None

@app.get("/test")
def test():
    return {"container_ip": _get_container_ip()}

@app.get("/")
def read_root():
    return {"message": "Hello World"}
