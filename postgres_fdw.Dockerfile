ARG PG_VERSION
FROM postgres:${PG_VERSION}-alpine as build

ARG FDW_VERSION

RUN apk --no-cache add curl python3 gcc g++ make musl-dev openssl-dev cmake curl-dev util-linux-dev;\
    chmod a+rwx /usr/local/lib/postgresql && \
    chmod a+rwx /usr/local/share/postgresql/extension && \
    mkdir -p /usr/local/share/doc/postgresql/contrib && \
    chmod a+rwx /usr/local/share/doc/postgresql/contrib

RUN wget -O fdw.zip -c https://github.com/adjust/clickhouse_fdw/archive/refs/tags/$FDW_VERSION.zip && \
	unzip fdw.zip && \
	cd clickhouse_fdw-$FDW_VERSION && mkdir build && cd build && cmake .. && make && DESTDIR=/tmp/data make install

FROM postgres:${PG_VERSION}-alpine as install
RUN apk --no-cache add libcurl
COPY --from=build /tmp/data/ /
