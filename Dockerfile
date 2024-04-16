FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive

RUN sed 's/main$/main universe/' -i /etc/apt/sources.list
RUN apt-get upgrade -y
RUN apt-get update

# Download and install stuff
RUN apt-get install -y -f build-essential xorg libssl-dev libxrender-dev wget git curl
RUN apt-get install -y --no-install-recommends xvfb libfontconfig libjpeg-turbo8 xfonts-75dpi fontconfig
RUN apt-get install -y vim wkhtmltopdf libssl-dev unixodbc
RUN apt-get install -y poppler-utils tesseract-ocr libtesseract-dev
RUN apt-get update

ENV HOME /home/vectara
ENV XDG_RUNTIME_DIR=/tmp

WORKDIR ${HOME}

SHELL ["/bin/bash", "-c"]

RUN apt-get install -y python3-pip
RUN pip3 install poetry

COPY poetry.lock pyproject.toml $HOME/
RUN poetry config virtualenvs.create false
RUN poetry install --only main
RUN playwright install --with-deps firefox

# Install additional large libraries for unstructured inference and PII detection
ARG INSTALL_EXTRA=false
COPY requirements.txt $HOME/
RUN if [ "$INSTALL_EXTRA" = "true" ]; then \
    pip3 install -r requirements.txt && \
    python3 -m spacy download en_core_web_lg; \
    fi

COPY *.py $HOME/
COPY core/*.py $HOME/core/
COPY crawlers/ $HOME/crawlers/
COPY config/ $HOME/config/

# Set environment variables
ENV CONFIG_FILE=$CONFIG_FILE
ENV PROFILE=$PROFILE
ENV VECTARA_API_KEY=$VECTARA_API_KEY
ENV VECTARA_CORPUS_ID=$VECTARA_CORPUS_ID
ENV VECTARA_CUSTOMER_ID=$VECTARA_CUSTOMER_ID

ENTRYPOINT ["/bin/bash", "-l", "-c"]
CMD ["echo 'Starting ingest.py script...' && python3 ingest.py"]