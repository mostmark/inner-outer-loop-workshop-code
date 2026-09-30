# Gateway Service (.NET 9) built as a container image with the Red Hat UBI .NET images.
# The workshop builds the gateway with S2I (dotnet:9.0 image stream) instead; this file is an
# alternative for local builds (podman build) or the Docker build strategy.

FROM registry.access.redhat.com/ubi8/dotnet-90:9.0 AS build
WORKDIR /opt/app-root/src
COPY --chown=1001:0 app.csproj .
RUN dotnet restore app.csproj
COPY --chown=1001:0 . .
RUN dotnet publish app.csproj -c Release -o /opt/app-root/app --no-restore

FROM registry.access.redhat.com/ubi8/dotnet-90-runtime:9.0
WORKDIR /opt/app-root/app
COPY --from=build /opt/app-root/app .
ENV ASPNETCORE_URLS=http://*:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "app.dll"]
