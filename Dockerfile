ARG ALPINE_VER=3.13
ARG LIBTORRENT_VER=latest
ARG FLEXGET_TARBALL="https://github.com/Flexget/Flexget/tarball/develop"
ARG FLEXGET_WEBUI_TARBALL="https://github.com/Flexget/webui/tarball/develop"

# Build UI
FROM node:lts-alpine as ui
ARG FLEXGET_WEBUI_TARBALL
ENV PATH /app/node_modules/.bin:$PATH

WORKDIR /app
RUN wget ${FLEXGET_WEBUI_TARBALL} -O ui.tar.gz && \
	tar --strip-components=1 -xzvf ui.tar.gz
RUN yarn install --frozen-lockfile
RUN yarn build

# Build rest
ARG ALPINE_VER
ARG LIBTORRENT_VER

FROM ghcr.io/wiserain/libtorrent:${LIBTORRENT_VER}-alpine${ALPINE_VER}-py3 AS libtorrent
FROM ghcr.io/linuxserver/baseimage-alpine:${ALPINE_VER}
LABEL maintainer="wiserain"
LABEL org.opencontainers.image.source https://github.com/wiserain/docker-flexget

ARG FLEXGET_TARBALL
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

RUN \
	echo "**** install frolvlad/alpine-python3 ****" && \
	apk add --no-cache python3 && \
	if [[ ! -e /usr/bin/python ]]; then ln -sf /usr/bin/python3 /usr/bin/python; fi && \
	python3 -m ensurepip && \
	rm -r /usr/lib/python*/ensurepip && \
	pip3 install --no-cache --upgrade pip setuptools wheel && \
	if [ ! -e /usr/bin/pip ]; then ln -s pip3 /usr/bin/pip; fi && \
	echo "**** install dependencies for plugin: telegram ****" && \
	apk add --no-cache --virtual=build-deps gcc python3-dev libffi-dev musl-dev openssl-dev && \
	pip install --upgrade python-telegram-bot==12.8 "cryptography<3.4" PySocks && \
	echo "**** install dependencies for plugin: cfscraper ****" && \
	apk add --no-cache --virtual=build-deps g++ gcc python3-dev libffi-dev openssl-dev && \
	pip install --upgrade cloudscraper && \
	echo "**** install dependencies for plugin: convert_magnet ****" && \
	apk add --no-cache boost-python3 libstdc++ && \
	echo "**** install dependencies for plugin: decompress ****" && \
	apk add --no-cache unrar && \
	pip install --upgrade \
	rarfile && \
	echo "**** install dependencies for plugin: transmission-rpc ****" && \
	apk add --no-cache --virtual=build-deps build-base python3-dev && \
	pip install --upgrade transmission-rpc && \
	echo "**** install dependencies for plugin: misc ****" && \
	pip install --upgrade \
	deluge-client \
	irc_bot
RUN \
	echo "**** install flexget ****" && \
	mkdir -p /tmp/flexget && \
	apk add --no-cache --virtual=build-deps gcc libxml2-dev libxslt-dev libc-dev python3-dev jpeg-dev g++ && \
	wget ${FLEXGET_TARBALL} -O /tmp/flexget.tar.gz && \
	tar --strip-components=1 -xzvf /tmp/flexget.tar.gz -C /tmp/flexget
COPY --from=ui /app/dist  /tmp/flexget/flexget/ui/v2/dist
RUN \
	cd /tmp/flexget && \
	python3 setup.py install && \
	apk del --purge --no-cache build-deps && \
	apk add --no-cache libxml2 libxslt jpeg
RUN \
	echo "**** system configurations ****" && \
	apk --no-cache add bash bash-completion tzdata && \
	echo "**** cleanup ****" && \
	rm -rf \
	/tmp/* \
	/root/.cache

# copy libtorrent libs
COPY --from=libtorrent /libtorrent-build/usr/lib/ /usr/lib/

# copy local files
COPY root/ /

# add default volumes
VOLUME /config /data
WORKDIR /config

# expose port for flexget webui
EXPOSE 5050 5050/tcp
