FROM python:3.13-alpine AS build
WORKDIR /src
COPY website ./website
COPY skillies ./skillies
COPY assets/brand ./assets/brand
RUN python3 website/build.py

FROM caddy:2-alpine
COPY website/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/dist/site /srv
ENV PORT=8080
EXPOSE 8080
