FROM pardahlman/sphinx

COPY ./source-codes/web/docs /docs
COPY README.md /docs
RUN export README=$(cat /docs/README.md) \
    sed -i -e "s|{README}|${README}|g" \
              /docs/index.rst