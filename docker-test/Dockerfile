FROM ghcr.io/indico/indico:latest

USER root

COPY messages-all.po /tmp/zh_Hant_TW_messages-all.po
COPY messages.mo     /tmp/zh_Hant_TW_messages.mo

# Install watchfiles (required by `indico run`) and inject our translation.
RUN set -ex && \
    /opt/indico/.venv/bin/pip install --quiet watchfiles && \
    TRANS_DIR=$(/opt/indico/.venv/bin/python3 -c \
        "from flask.helpers import get_root_path; print(get_root_path('indico'))") && \
    TRANS_DIR="$TRANS_DIR/translations/zh_Hant_TW/LC_MESSAGES" && \
    mkdir -p "$TRANS_DIR" && \
    cp /tmp/zh_Hant_TW_messages-all.po "$TRANS_DIR/messages-all.po" && \
    cp /tmp/zh_Hant_TW_messages.mo     "$TRANS_DIR/messages.mo" && \
    echo "Installed zh_Hant_TW translations at $TRANS_DIR"

USER indico
