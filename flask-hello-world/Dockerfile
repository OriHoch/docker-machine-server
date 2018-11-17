FROM python
RUN python3 -m pip install flask
COPY hello.py .
ENV FLASK_APP=hello.py
ENTRYPOINT ["flask", "run"]
