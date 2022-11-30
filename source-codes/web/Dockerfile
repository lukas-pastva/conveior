FROM pardahlman/sphinx

COPY ./source-codes/web/docs /docs
COPY ./README.md /docs/README.md
RUN sed -i -e "s|{README}|$(cat /docs/README.md)|g" \
              /docs/index.rst