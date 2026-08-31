FROM mcr.microsoft.com/powershell:7.5-alpine-3.20

ARG KUBECTL_VERSION=v1.35.7
RUN wget -q "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -O /usr/local/bin/kubectl \
    && wget -q "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" -O /tmp/kubectl.sha256 \
    && echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/kubectl \
    && addgroup -g 10001 dashboard \
    && adduser -D -u 10001 -G dashboard dashboard

WORKDIR /app
ENV HOME=/tmp
ENV XDG_CACHE_HOME=/tmp/.cache
ENV POWERSHELL_TELEMETRY_OPTOUT=1
COPY scripts/LabHealth.ps1 scripts/LabHealth.ps1
COPY providers/azure/aks/scripts/Profile-Aks.ps1 providers/azure/aks/scripts/Profile-Aks.ps1
COPY providers/azure/aks/profiles providers/azure/aks/profiles
COPY dashboard dashboard
RUN chown -R 10001:10001 /app
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["pwsh","-NoLogo","-NoProfile","-File","/app/dashboard/server.ps1"]
