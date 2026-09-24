FROM ghcr.io/osgeo/gdal:ubuntu-small-latest

WORKDIR /app

COPY make_transparent.py /app/make_transparent.py

ENTRYPOINT ["python3", "/app/make_transparent.py"]